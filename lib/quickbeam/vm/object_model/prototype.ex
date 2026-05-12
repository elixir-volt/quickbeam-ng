defmodule QuickBEAM.VM.ObjectModel.Prototype do
  @moduledoc "Shared JavaScript prototype access and chain helpers."

  import QuickBEAM.VM.Heap.Keys, only: [proto: 0]

  alias QuickBEAM.VM.Heap

  def get({:obj, ref}) do
    case Heap.get_obj(ref, %{}) do
      {:qb_arr, _} -> Heap.get_array_proto(ref)
      data when is_list(data) -> Heap.get_array_proto(ref)
      map when is_map(map) -> object_map_prototype(ref, map)
      _ -> nil
    end
  end

  def get({:qb_arr, _}), do: Heap.get_func_proto()
  def get(value) when is_list(value), do: QuickBEAM.VM.Runtime.global_class_proto("Array")
  def get({:builtin, _, _} = callable), do: callable_prototype(callable)
  def get({:closure, _, _} = callable), do: callable_prototype(callable)
  def get(%QuickBEAM.VM.Function{}), do: Heap.get_func_proto()
  def get(value) when is_function(value), do: Heap.get_func_proto()

  def get(value) when is_integer(value) or is_float(value),
    do: QuickBEAM.VM.Runtime.global_class_proto("Number")

  def get(value) when is_binary(value), do: QuickBEAM.VM.Runtime.global_class_proto("String")
  def get(value) when is_boolean(value), do: QuickBEAM.VM.Runtime.global_class_proto("Boolean")
  def get(_), do: nil

  def set({:obj, ref}, new_proto) do
    case Heap.get_obj(ref, %{}) do
      map when is_map(map) -> Heap.put_obj(ref, Map.put(map, proto(), new_proto))
      _ -> :ok
    end
  end

  def set(_, _), do: :ok

  def chain_contains?(value, target_ref),
    do: chain_contains?(get(value), target_ref, MapSet.new())

  defp chain_contains?({:obj, ref}, target_ref, _seen) when ref == target_ref, do: true

  defp chain_contains?({:obj, ref} = object, target_ref, seen) do
    if MapSet.member?(seen, ref) do
      false
    else
      chain_contains?(get(object), target_ref, MapSet.put(seen, ref))
    end
  end

  defp chain_contains?(_, _target_ref, _seen), do: false

  defp object_map_prototype(ref, map) do
    cond do
      Map.has_key?(map, :__internal_proto__) -> Map.get(map, :__internal_proto__)
      Heap.get_prop_desc(ref, proto()) -> Heap.get_object_prototype()
      true -> Map.get(map, proto(), nil)
    end
  end

  defp callable_prototype(callable) do
    case Map.get(Heap.get_ctor_statics(callable), "__proto__") do
      nil -> Heap.get_func_proto()
      parent -> parent
    end
  end
end
