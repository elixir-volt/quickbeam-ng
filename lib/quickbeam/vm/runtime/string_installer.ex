defmodule QuickBEAM.VM.Runtime.StringInstaller do
  @moduledoc "Installs the String constructor, prototype methods, wrapper slot, and iterator metadata."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.{PropertyDescriptor, Put, WrappedPrimitive}
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.Globals.Constructors
  alias QuickBEAM.VM.Runtime.String, as: JSString

  @methods ~w(charAt charCodeAt codePointAt indexOf lastIndexOf includes startsWith endsWith slice substring substr split trim trimStart trimEnd toUpperCase toLowerCase toLocaleUpperCase toLocaleLowerCase repeat padStart padEnd replace replaceAll match matchAll localeCompare search normalize concat toString valueOf at isWellFormed toWellFormed)

  @doc "Returns the global String constructor binding."
  def constructor do
    ctor =
      ConstructorRegistry.register("String", &Constructors.string/2,
        module: JSString,
        auto_proto: true
      )

    install_prototype_methods(ctor)
    install_prototype_metadata(ctor)
    install_static_descriptors(ctor)

    ctor
  end

  defp install_prototype_methods(ctor) do
    with_prototype(ctor, fn proto_ref ->
      for name <- @methods do
        Heap.put_obj_key(proto_ref, name, JSString.proto_property(name))
        Heap.put_prop_desc(proto_ref, name, PropertyDescriptor.method())
      end
    end)
  end

  defp install_prototype_metadata(ctor) do
    with_prototype(ctor, fn proto_ref ->
      proto_ref
      |> Heap.get_obj(%{})
      |> Map.put_new(WrappedPrimitive.slot(:string), "")
      |> maybe_put_object_prototype()
      |> then(&Heap.put_obj(proto_ref, &1))

      Put.put({:obj, proto_ref}, "constructor", ctor)
      Heap.put_prop_desc(proto_ref, "constructor", PropertyDescriptor.method())
      install_iterator(proto_ref)
    end)
  end

  defp maybe_put_object_prototype(map) do
    case Heap.get_object_prototype() do
      {:obj, _} = object_proto -> Map.put(map, "__proto__", object_proto)
      _ -> map
    end
  end

  defp install_iterator(proto_ref) do
    sym_iterator = {:symbol, "Symbol.iterator"}

    iterator =
      case JSString.proto_property(sym_iterator) do
        {:builtin, _name, callback} -> {:builtin, "[Symbol.iterator]", callback}
        other -> other
      end

    Heap.put_obj_key(proto_ref, sym_iterator, iterator)
    Heap.put_prop_desc(proto_ref, sym_iterator, PropertyDescriptor.method())
    Heap.put_ctor_static(iterator, "length", 0)
    Heap.put_ctor_static(iterator, "name", "[Symbol.iterator]")
    Heap.put_ctor_prop_desc(iterator, "length", PropertyDescriptor.hidden_readonly())
    Heap.put_ctor_prop_desc(iterator, "name", PropertyDescriptor.hidden_readonly())
  end

  defp install_static_descriptors(ctor) do
    Heap.put_ctor_static(ctor, "length", 1)
    Heap.put_ctor_prop_desc(ctor, "length", PropertyDescriptor.hidden_readonly())
    Heap.put_prop_desc(ctor, "prototype", PropertyDescriptor.prototype())
  end

  defp with_prototype(ctor, fun) do
    case Heap.get_ctor_statics(ctor)["prototype"] do
      {:obj, proto_ref} -> fun.(proto_ref)
      _ -> :ok
    end
  end
end
