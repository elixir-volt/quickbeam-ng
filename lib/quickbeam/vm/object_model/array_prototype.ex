defmodule QuickBEAM.VM.ObjectModel.ArrayPrototype do
  @moduledoc "Shared helpers for Array prototype-chain behavior."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.Put

  def has_property?(array_ref, key) do
    Put.has_property(Heap.get_array_proto(array_ref), key) or
      Put.has_property(Heap.get_object_prototype(), key)
  end
end
