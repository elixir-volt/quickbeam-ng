defmodule QuickBEAM.VM.ObjectModel.TypedArrayObjectGet do
  @moduledoc "Own-property lookup for heap-backed typed array objects."

  import QuickBEAM.VM.Heap.Keys, only: [typed_array: 0]

  alias QuickBEAM.VM.ObjectModel.TypedArrayExoticGet
  alias QuickBEAM.VM.Runtime.TypedArray

  def typed_array_map?(%{typed_array() => true}), do: true
  def typed_array_map?(_), do: false

  def own_property(obj, map, key, callbacks)

  def own_property(obj, _map, "length", _callbacks),
    do: if(TypedArray.out_of_bounds?(obj), do: 0, else: TypedArray.element_count(obj))

  def own_property(obj, _map, "byteLength", _callbacks),
    do: if(TypedArray.out_of_bounds?(obj), do: 0, else: TypedArray.current_byte_length(obj))

  def own_property(obj, map, "byteOffset", _callbacks),
    do: if(TypedArray.out_of_bounds?(obj), do: 0, else: Map.get(map, "byteOffset", 0))

  def own_property(obj, map, key, callbacks),
    do:
      TypedArrayExoticGet.property(obj, map, key, fn ->
        callbacks.get_map_property.(map, key, obj)
      end)
end
