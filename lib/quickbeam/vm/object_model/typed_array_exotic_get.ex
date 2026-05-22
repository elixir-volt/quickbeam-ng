defmodule QuickBEAM.VM.ObjectModel.TypedArrayExoticGet do
  @moduledoc "TypedArray exotic property lookup helpers."

  import QuickBEAM.VM.Heap.Keys, only: [key_order: 0]

  alias QuickBEAM.VM.ObjectModel.PropertyKey
  alias QuickBEAM.VM.Runtime.TypedArray

  def property(obj, map, key, fallback) when is_function(fallback, 0) do
    case PropertyKey.array_index(key) do
      {:ok, idx} -> indexed_property(obj, map, key, idx)
      :error -> fallback.()
    end
  end

  defp indexed_property(obj, map, key, idx) do
    if Map.has_key?(map, key_order()) do
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> TypedArray.get_element(obj, idx)
      end
    else
      TypedArray.get_element(obj, idx)
    end
  end
end
