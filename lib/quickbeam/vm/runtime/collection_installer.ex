defmodule QuickBEAM.VM.Runtime.CollectionInstaller do
  @moduledoc "Installs Map/Set and weak collection constructors, prototypes, and well-known metadata."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.{PropertyDescriptor, Put}
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.Map, as: JSMap
  alias QuickBEAM.VM.Runtime.Set, as: JSSet

  @map_methods ~w(get set has delete clear keys values entries forEach getOrInsert getOrInsertComputed)
  @set_methods ~w(has add delete clear values keys entries forEach difference intersection union symmetricDifference isSubsetOf isSupersetOf isDisjointFrom)
  @map_iterator_methods ~w(keys values entries)
  @set_iterator_methods ~w(keys values entries)

  @doc "Returns global bindings for Map, Set, WeakMap, and WeakSet."
  def bindings do
    %{
      "Map" => map(),
      "Set" => set(),
      "WeakMap" => weak_map(),
      "WeakSet" => weak_set()
    }
  end

  defp map do
    ctor = ConstructorRegistry.register("Map", JSMap.constructor(), auto_proto: true)
    Heap.put_ctor_prop_desc(ctor, "prototype", PropertyDescriptor.prototype())

    install_static_group_by(ctor)
    install_species(ctor)

    with_prototype(ctor, fn proto_ref ->
      Heap.put_obj_key(proto_ref, "__proto__", Heap.get_object_prototype())
      install_methods(proto_ref, JSMap, @map_methods, @map_iterator_methods)
      install_symbol_iterator(proto_ref, JSMap)
      install_size_accessor(proto_ref, "Map", &JSMap.size/1)
      install_to_string_tag(proto_ref, "Map")
      install_constructor(proto_ref, ctor)
    end)

    ctor
  end

  defp set do
    ctor = ConstructorRegistry.register("Set", JSSet.constructor(), auto_proto: true)

    with_prototype(ctor, fn proto_ref ->
      Heap.put_obj_key(proto_ref, "__proto__", Heap.get_object_prototype())
      install_methods(proto_ref, JSSet, @set_methods, @set_iterator_methods)
      install_symbol_iterator(proto_ref, JSSet)
      install_size_accessor(proto_ref, "Set", &JSSet.size/1)
      install_to_string_tag(proto_ref, "Set")
      install_constructor(proto_ref, ctor)
    end)

    install_species(ctor)
    ctor
  end

  defp weak_map do
    ctor = ConstructorRegistry.register("WeakMap", JSMap.weak_constructor(), auto_proto: true)
    Heap.put_ctor_prop_desc(ctor, "prototype", PropertyDescriptor.prototype())

    with_prototype(ctor, fn proto_ref ->
      Heap.put_obj_key(proto_ref, "__proto__", Heap.get_object_prototype())
      Heap.put_prop_desc(proto_ref, "constructor", PropertyDescriptor.method())

      install_weak_methods(
        proto_ref,
        JSMap,
        ~w(get set has delete getOrInsert getOrInsertComputed)
      )

      install_to_string_tag(proto_ref, "WeakMap")
    end)

    ctor
  end

  defp weak_set do
    ctor = ConstructorRegistry.register("WeakSet", JSSet.weak_constructor(), auto_proto: true)
    Heap.put_ctor_prop_desc(ctor, "prototype", PropertyDescriptor.prototype())

    with_prototype(ctor, fn proto_ref ->
      Heap.put_obj_key(proto_ref, "__proto__", Heap.get_object_prototype())
      Heap.put_prop_desc(proto_ref, "constructor", PropertyDescriptor.method())
      install_weak_methods(proto_ref, JSSet, ~w(add has delete))
      install_to_string_tag(proto_ref, "WeakSet")
    end)

    ctor
  end

  defp install_static_group_by(ctor) do
    group_by = {:builtin, "groupBy", fn args, _this -> JSMap.group_by(args) end}
    Heap.put_ctor_static(ctor, "groupBy", group_by)
  end

  defp install_species(ctor) do
    sym_species = {:symbol, "Symbol.species"}

    Heap.put_ctor_static(
      ctor,
      sym_species,
      {:accessor, {:builtin, "get [Symbol.species]", fn _args, this -> this end}, nil}
    )

    Heap.put_ctor_prop_desc(ctor, sym_species, PropertyDescriptor.accessor())
  end

  defp with_prototype(ctor, fun) do
    case Heap.get_ctor_statics(ctor)["prototype"] do
      {:obj, proto_ref} -> fun.(proto_ref)
      _ -> :ok
    end
  end

  defp install_methods(proto_ref, module, names, zero_length_names) do
    for name <- names do
      method = module.proto_property(name)
      Heap.put_obj_key(proto_ref, name, method)
      install_zero_length(method, name in zero_length_names)
      Heap.put_prop_desc(proto_ref, name, PropertyDescriptor.method())
    end
  end

  defp install_weak_methods(proto_ref, module, names) do
    for name <- names do
      Heap.put_obj_key(proto_ref, name, module.weak_proto_property(name))
      Heap.put_prop_desc(proto_ref, name, PropertyDescriptor.method())
    end
  end

  defp install_zero_length(method, true) do
    Heap.put_ctor_static(method, "length", 0)
    Heap.put_ctor_prop_desc(method, "length", PropertyDescriptor.hidden_readonly())
  end

  defp install_zero_length(_method, false), do: :ok

  defp install_symbol_iterator(proto_ref, module) do
    sym_iter = {:symbol, "Symbol.iterator"}
    Heap.put_obj_key(proto_ref, sym_iter, module.proto_property(sym_iter))
    Heap.put_prop_desc(proto_ref, sym_iter, PropertyDescriptor.method())
  end

  defp install_size_accessor(proto_ref, _label, size_fun) do
    Heap.put_obj_key(
      proto_ref,
      "size",
      {:accessor, {:builtin, "get size", fn _args, this -> size_fun.(this) end}, nil}
    )

    Heap.put_prop_desc(proto_ref, "size", PropertyDescriptor.accessor())
  end

  defp install_to_string_tag(proto_ref, label) do
    sym_to_string_tag = {:symbol, "Symbol.toStringTag"}
    Heap.put_obj_key(proto_ref, sym_to_string_tag, label)
    Heap.put_prop_desc(proto_ref, sym_to_string_tag, PropertyDescriptor.hidden_readonly())
  end

  defp install_constructor(proto_ref, ctor) do
    Put.put({:obj, proto_ref}, "constructor", ctor)
    Heap.put_prop_desc(proto_ref, "constructor", PropertyDescriptor.method())
  end
end
