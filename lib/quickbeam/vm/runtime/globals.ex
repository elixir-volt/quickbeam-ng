defmodule QuickBEAM.VM.Runtime.Globals do
  @moduledoc "JS global scope: constructors, global functions, and the binding map."

  import QuickBEAM.VM.Builtin, only: [object: 1]

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.PropertyDescriptor
  alias QuickBEAM.VM.Runtime

  alias QuickBEAM.VM.Runtime.WebAPIs

  alias QuickBEAM.VM.Runtime.{
    ArrayBuffer,
    ArrayInstaller,
    Boolean,
    CollectionInstaller,
    Console,
    DateInstaller,
    Errors,
    GlobalNumeric,
    GlobalThisInstaller,
    JSON,
    Math,
    NumberInstaller,
    Object,
    PromiseBuiltins,
    Reflect,
    RegExpInstaller,
    StringInstaller,
    Symbol,
    Test262Host,
    TypedArrayInstaller
  }

  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.Globals.{Constructors, Functions}

  @doc "Builds the runtime value represented by this module."
  def build do
    obj_proto = ensure_object_prototype()
    obj_ctor = register("Object", &Constructors.object/2, module: Object, prototype: obj_proto)

    # Set constructor on Object.prototype
    {:obj, proto_ref} = obj_proto
    proto_data = Heap.get_obj(proto_ref, %{})

    if is_map(proto_data),
      do: Heap.put_obj(proto_ref, Map.put(proto_data, "constructor", obj_ctor))

    bindings()
    |> Map.put("Object", obj_ctor)
    |> Map.merge(TypedArrayInstaller.bindings())
    |> Map.merge(CollectionInstaller.bindings())
    |> Map.merge(Errors.bindings())
    |> tap(&Heap.put_global_cache/1)
    |> Map.merge(WebAPIs.bindings())
    |> tap(&GlobalThisInstaller.install/1)
    |> tap(&Heap.put_global_cache/1)
  end

  # ── Binding map ──

  defp bindings do
    %{
      "$262" => Test262Host.object(),
      "Array" => ArrayInstaller.constructor(),
      "String" => StringInstaller.constructor(),
      "Number" => NumberInstaller.constructor(),
      "BigInt" => register("BigInt", &Constructors.bigint/2, auto_proto: true),
      "Boolean" => register("Boolean", Boolean.constructor(), module: Boolean, auto_proto: true),
      "Function" =>
        (fn ->
           fun_ctor =
             register("Function", &Constructors.function/2,
               prototype: QuickBEAM.VM.Runtime.Function.prototype()
             )

           proto = Heap.get_ctor_statics(fun_ctor)["prototype"]

           if match?({:obj, _}, proto),
             do: QuickBEAM.VM.ObjectModel.Put.put(proto, "constructor", fun_ctor)

           Heap.put_prop_desc(fun_ctor, "prototype", PropertyDescriptor.prototype())

           fun_ctor
         end).(),
      "RegExp" => RegExpInstaller.constructor(),
      "Date" => DateInstaller.constructor(),
      "Promise" =>
        register("Promise", PromiseBuiltins.constructor(),
          module: PromiseBuiltins,
          prototype: PromiseBuiltins.prototype()
        ),
      "Symbol" => register("Symbol", Symbol.constructor(), module: Symbol, auto_proto: true),
      "DataView" => register("DataView", fn _, _ -> Runtime.new_object() end),
      "ArrayBuffer" =>
        (
          ab_ctor = register("ArrayBuffer", &ArrayBuffer.constructor/2, auto_proto: true)
          install_prototype_methods(ab_ctor, ArrayBuffer, ArrayBuffer.proto_property_names())

          Heap.put_ctor_static(
            ab_ctor,
            {:symbol, "Symbol.species"},
            {:accessor, {:builtin, "get [Symbol.species]", fn _, _ -> ab_ctor end}, nil}
          )

          ab_ctor
        ),
      "Proxy" =>
        (fn ->
           ctor = register("Proxy", &Constructors.proxy/2)

           Heap.put_ctor_static(
             ctor,
             "revocable",
             {:builtin, "revocable",
              fn [target, handler | _], _ ->
                proxy = Constructors.proxy([target, handler], nil)

                revoke_fn =
                  {:builtin, "revoke",
                   fn _, _ ->
                     {:obj, proxy_ref} = proxy
                     Heap.put_obj_key(proxy_ref, "__proxy_revoked__", true)

                     :undefined
                   end}

                Heap.wrap(%{"proxy" => proxy, "revoke" => revoke_fn})
              end}
           )

           ctor
         end).(),
      "Math" => Math.object(),
      "JSON" => JSON.object(),
      "Reflect" => Reflect.object() |> Reflect.install_metadata(),
      "console" => Console.object(),
      "parseInt" => builtin("parseInt", &GlobalNumeric.parse_int/2),
      "parseFloat" => builtin("parseFloat", &GlobalNumeric.parse_float/2),
      "isNaN" => builtin("isNaN", &GlobalNumeric.nan?/2),
      "isFinite" => builtin("isFinite", &GlobalNumeric.finite?/2),
      "eval" => builtin("eval", &Functions.js_eval/2),
      "decodeURI" => builtin("decodeURI", &Functions.decode_uri/2),
      "decodeURIComponent" => builtin("decodeURIComponent", &Functions.decode_uri_component/2),
      "encodeURI" => builtin("encodeURI", &Functions.encode_uri/2),
      "encodeURIComponent" => builtin("encodeURIComponent", &Functions.encode_uri_component/2),
      "require" => builtin("require", &Functions.js_require/2),
      "structuredClone" =>
        builtin("structuredClone", fn
          [val | _], _ -> QuickBEAM.VM.Runtime.StructuredClone.clone(val)
          [], _ -> nil
        end),
      "queueMicrotask" => builtin("queueMicrotask", &Functions.queue_microtask/2),
      "gc" => builtin("gc", fn _, _ -> :undefined end),
      "os" => Heap.wrap(%{"platform" => "elixir"}),
      "qjs" =>
        object do
          method "getStringKind" do
            s = hd(args)
            if is_binary(s) and byte_size(s) > 256, do: 1, else: 0
          end
        end,
      "globalThis" => Runtime.new_object(),
      "NaN" => :nan,
      "Infinity" => :infinity,
      "undefined" => :undefined
    }
    |> Map.merge(QuickBEAM.VM.Builtin.Discovery.bindings())
  end

  # ── Registration helpers ──

  defp builtin(name, fun), do: {:builtin, name, fun}

  defp register(name, constructor, opts \\ []) do
    ConstructorRegistry.register(name, constructor, opts)
  end

  defp ensure_object_prototype do
    case Heap.get_object_prototype() do
      nil -> Object.build_prototype()
      existing -> existing
    end
  end

  defp install_prototype_methods(ctor, module, names) do
    case Heap.get_ctor_statics(ctor)["prototype"] do
      {:obj, proto_ref} ->
        for name <- names do
          Heap.put_obj_key(proto_ref, name, module.proto_property(name))

          Heap.put_prop_desc(proto_ref, name, PropertyDescriptor.method())
        end

      _ ->
        :ok
    end
  end
end
