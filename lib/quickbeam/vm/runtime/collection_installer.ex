defmodule QuickBEAM.VM.Runtime.CollectionInstaller do
  @moduledoc "Installs Map/Set and weak collection constructors, prototypes, and well-known metadata."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.PropertyDescriptor
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.InstallerHelpers
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
    InstallerHelpers.install_species(ctor)

    InstallerHelpers.with_prototype(ctor, fn proto_ref ->
      InstallerHelpers.install_object_parent(proto_ref)

      InstallerHelpers.install_methods(proto_ref, JSMap, @map_methods,
        zero_length: @map_iterator_methods
      )

      InstallerHelpers.install_symbol_iterator(proto_ref, JSMap)
      InstallerHelpers.install_accessor(proto_ref, "size", "get size", &JSMap.size/1)
      InstallerHelpers.install_to_string_tag(proto_ref, "Map")
      InstallerHelpers.install_constructor_link(proto_ref, ctor)
    end)

    ctor
  end

  defp set do
    ctor = ConstructorRegistry.register("Set", JSSet.constructor(), auto_proto: true)

    InstallerHelpers.with_prototype(ctor, fn proto_ref ->
      InstallerHelpers.install_object_parent(proto_ref)

      InstallerHelpers.install_methods(proto_ref, JSSet, @set_methods,
        zero_length: @set_iterator_methods
      )

      InstallerHelpers.install_symbol_iterator(proto_ref, JSSet)
      InstallerHelpers.install_accessor(proto_ref, "size", "get size", &JSSet.size/1)
      InstallerHelpers.install_to_string_tag(proto_ref, "Set")
      InstallerHelpers.install_constructor_link(proto_ref, ctor)
    end)

    InstallerHelpers.install_species(ctor)
    ctor
  end

  defp weak_map do
    ctor = ConstructorRegistry.register("WeakMap", JSMap.weak_constructor(), auto_proto: true)
    Heap.put_ctor_prop_desc(ctor, "prototype", PropertyDescriptor.prototype())

    InstallerHelpers.with_prototype(ctor, fn proto_ref ->
      InstallerHelpers.install_object_parent(proto_ref)
      Heap.put_prop_desc(proto_ref, "constructor", PropertyDescriptor.method())

      InstallerHelpers.install_methods_with(
        proto_ref,
        ~w(get set has delete getOrInsert getOrInsertComputed),
        &JSMap.weak_proto_property/1
      )

      InstallerHelpers.install_to_string_tag(proto_ref, "WeakMap")
    end)

    ctor
  end

  defp weak_set do
    ctor = ConstructorRegistry.register("WeakSet", JSSet.weak_constructor(), auto_proto: true)
    Heap.put_ctor_prop_desc(ctor, "prototype", PropertyDescriptor.prototype())

    InstallerHelpers.with_prototype(ctor, fn proto_ref ->
      InstallerHelpers.install_object_parent(proto_ref)
      Heap.put_prop_desc(proto_ref, "constructor", PropertyDescriptor.method())

      InstallerHelpers.install_methods_with(
        proto_ref,
        ~w(add has delete),
        &JSSet.weak_proto_property/1
      )

      InstallerHelpers.install_to_string_tag(proto_ref, "WeakSet")
    end)

    ctor
  end

  defp install_static_group_by(ctor) do
    group_by = {:builtin, "groupBy", fn args, _this -> JSMap.group_by(args) end}
    Heap.put_ctor_static(ctor, "groupBy", group_by)
  end
end
