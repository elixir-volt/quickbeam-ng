defmodule QuickBEAM.VM.Runtime.Errors do
  @moduledoc "JS Error constructors and prototype: `Error`, `TypeError`, `RangeError`, and the other standard error types."

  @behaviour QuickBEAM.VM.Runtime.BindingProvider

  import QuickBEAM.VM.Builtin, only: [arg: 3, object: 2]

  alias QuickBEAM.VM.{Heap, Invocation}
  alias QuickBEAM.VM.JSThrow
  alias QuickBEAM.VM.ObjectModel.{Get, HasProperty, PropertyDescriptor}
  alias QuickBEAM.VM.Semantics.Iterators
  alias QuickBEAM.VM.Runtime
  alias QuickBEAM.VM.Runtime.Constructors
  alias QuickBEAM.VM.Stacktrace

  @error_types ~w(Error TypeError RangeError SyntaxError ReferenceError URIError EvalError AggregateError)

  @doc "Returns the JavaScript global bindings provided by this module."
  def bindings do
    error_proto_ref = make_ref()
    error_ctor = {:builtin, "Error", fn args, _this -> error_constructor("Error", args) end}

    error_tostring =
      {:builtin, "toString",
       fn _args, this ->
         unless match?({:obj, _}, this) do
           JSThrow.type_error!("Error.prototype.toString called on non-object")
         end

         name =
           case QuickBEAM.VM.ObjectModel.Get.get(this, "name") do
             nil -> "Error"
             :undefined -> "Error"
             n -> stringify_error_slot(n)
           end

         msg =
           case QuickBEAM.VM.ObjectModel.Get.get(this, "message") do
             nil -> ""
             :undefined -> ""
             m -> stringify_error_slot(m)
           end

         cond do
           name == "" -> msg
           msg == "" -> name
           true -> name <> ": " <> msg
         end
       end}

    Heap.put_obj(
      error_proto_ref,
      object heap: false do
        prop("__proto__", Heap.get_object_prototype())
        prop("name", "Error")
        prop("message", "")
        prop("constructor", error_ctor)
        prop("toString", error_tostring)
      end
    )

    Heap.put_prop_desc(error_proto_ref, "name", PropertyDescriptor.method())
    Heap.put_prop_desc(error_proto_ref, "message", PropertyDescriptor.method())
    Heap.put_prop_desc(error_proto_ref, "constructor", PropertyDescriptor.method())
    Heap.put_prop_desc(error_proto_ref, "toString", PropertyDescriptor.method())

    Constructors.put_prototype(error_ctor, {:obj, error_proto_ref})
    install_function_parent(error_ctor)
    Heap.put_ctor_prop_desc(error_ctor, "prototype", PropertyDescriptor.prototype())

    Heap.put_ctor_static(
      error_ctor,
      "isError",
      {:builtin, "isError",
       fn args, _ ->
         case arg(args, 0, :undefined) do
           {:obj, ref} ->
             case Heap.get_obj(ref, %{}) do
               map when is_map(map) -> Map.has_key?(map, "__error_name__")
               _ -> false
             end
           _ -> false
         end
       end}
    )

    Heap.put_ctor_prop_desc(error_ctor, "isError", PropertyDescriptor.method())

    Heap.put_ctor_static(
      error_ctor,
      "captureStackTrace",
      {:builtin, "captureStackTrace",
       fn
         [], _ ->
           JSThrow.type_error!("Cannot convert undefined to object")

         [obj | rest], _ ->
           filter_fun = arg(rest, 0, nil)

           case obj do
             {:obj, _} -> Stacktrace.attach_stack(obj, filter_fun)
             _ -> :ok
           end

           :undefined
       end}
    )

    Heap.put_ctor_static(error_ctor, "prepareStackTrace", :undefined)
    Heap.put_ctor_static(error_ctor, "stackTraceLimit", 10)

    derived =
      for name <- Enum.reject(@error_types, &(&1 == "Error")), into: %{} do
        proto_ref = make_ref()
        ctor = {:builtin, name, fn args, _this -> construct_error(name, args) end}

        Heap.put_obj(
          proto_ref,
          object heap: false do
            prop("__proto__", {:obj, error_proto_ref})
            prop("name", name)
            prop("message", "")
            prop("constructor", ctor)
          end
        )

        Heap.put_prop_desc(proto_ref, "name", PropertyDescriptor.method())
        Heap.put_prop_desc(proto_ref, "message", PropertyDescriptor.method())
        Heap.put_prop_desc(proto_ref, "constructor", PropertyDescriptor.method())

        Constructors.put_prototype(ctor, {:obj, proto_ref})
        Heap.put_ctor_prop_desc(ctor, "prototype", PropertyDescriptor.prototype())
        Heap.put_ctor_static(ctor, "__proto__", error_ctor)
        {name, ctor}
      end

    Map.put(derived, "Error", error_ctor)
  end

  defp construct_error("AggregateError", args), do: aggregate_error_constructor(args)
  defp construct_error(name, args), do: error_constructor(name, args)

  defp error_constructor(name, args) do
    msg = arg(args, 0, :undefined)
    message = if msg == :undefined, do: "", else: stringify_error_slot(msg)
    error = Heap.make_error(message, name)
    if msg == :undefined, do: delete_message(error)
    maybe_install_cause(error, arg(args, 1, :undefined))
    Stacktrace.attach_stack(error)
  end

  defp maybe_install_cause({:obj, error_ref}, {:obj, _} = options) do
    if HasProperty.has_property?(options, "cause") do
      Heap.put_obj_key(error_ref, "cause", Get.get(options, "cause"))
      Heap.put_prop_desc(error_ref, "cause", PropertyDescriptor.method())
    end
  end

  defp maybe_install_cause(_error, _options), do: :ok

  defp aggregate_error_constructor(args) do
    errors = arg(args, 0, :undefined)
    message_arg = arg(args, 1, :undefined)
    options = arg(args, 2, :undefined)
    message = if message_arg == :undefined, do: "", else: stringify_error_slot(message_arg)
    error = Heap.make_error(message, "AggregateError")
    if message_arg == :undefined, do: delete_message(error)

    with {:obj, ref} <- error do
      Heap.put_obj_key(ref, "errors", Heap.wrap(iterable_list(errors)))
      Heap.put_prop_desc(ref, "errors", PropertyDescriptor.method())
    end

    maybe_install_cause(error, options)
    Stacktrace.attach_stack(error)
  end

  defp iterable_list(errors) when errors in [nil, :undefined],
    do: JSThrow.type_error!("object is not iterable")

  defp iterable_list({:obj, ref} = errors) do
    case Heap.get_obj(ref, %{}) do
      {:qb_arr, arr} ->
        :array.to_list(arr)

      map when is_map(map) ->
        sym_iter = {:symbol, "Symbol.iterator"}
        iter_fn = Get.get(errors, sym_iter)

        cond do
          QuickBEAM.VM.Builtin.callable?(iter_fn) ->
            iter = Invocation.invoke_with_receiver(iter_fn, [], errors)
            unless match?({:obj, _}, iter), do: JSThrow.type_error!("iterator is not an object")
            next_fn = Get.get(iter, "next")
            unless QuickBEAM.VM.Builtin.callable?(next_fn), do: JSThrow.type_error!("iterator.next is not callable")
            collect_iterable(iter, next_fn, [])

          QuickBEAM.VM.Builtin.callable?(Get.get(errors, "next")) ->
            collect_iterable(errors, Get.get(errors, "next"), [])

          true ->
            JSThrow.type_error!("object is not iterable")
        end

      _ ->
        JSThrow.type_error!("object is not iterable")
    end
  end

  defp iterable_list(errors) do
    {iter, next_fn} = Iterators.for_of_start(errors)
    collect_iterable(iter, next_fn, [])
  end

  defp collect_iterable({:list_iter, [head | tail]}, next_fn, acc),
    do: collect_iterable({:list_iter, tail}, next_fn, [head | acc])

  defp collect_iterable({:list_iter, []}, _next_fn, acc), do: Enum.reverse(acc)

  defp collect_iterable(iter, next_fn, acc) do
    result = Invocation.invoke_with_receiver(next_fn, [], iter)
    unless match?({:obj, _}, result), do: JSThrow.type_error!("iterator result is not an object")

    if Get.get(result, "done") == true do
      Enum.reverse(acc)
    else
      collect_iterable(iter, next_fn, [Get.get(result, "value") | acc])
    end
  end

  defp delete_message({:obj, ref}) do
    Heap.put_obj(ref, Map.delete(Heap.get_obj(ref, %{}), "message"))
    Heap.delete_prop_desc(ref, "message")
  end

  defp stringify_error_slot({:symbol, _}),
    do: JSThrow.type_error!("Cannot convert a Symbol value to a string")

  defp stringify_error_slot({:symbol, _, _}),
    do: JSThrow.type_error!("Cannot convert a Symbol value to a string")

  defp stringify_error_slot(value), do: Runtime.stringify(value)

  defp install_function_parent(ctor) do
    case Heap.get_func_proto() do
      {:obj, function_proto_ref} = function_proto ->
        Heap.put_ctor_static(ctor, "__proto__", function_proto)

        case Heap.get_obj(function_proto_ref, %{}) do
          %{"constructor" => function_ctor} -> Heap.put_ctor_static(ctor, "constructor", function_ctor)
          _ -> :ok
        end

      _ ->
        :ok
    end
  end
end
