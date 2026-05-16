defmodule QuickBEAM.VM.Heap.ProcessKeysTest do
  use ExUnit.Case, async: false

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.Heap.ProcessKeys

  test "owned? classifies heap process dictionary keys" do
    assert ProcessKeys.owned?(1)
    assert ProcessKeys.owned?(make_ref())
    assert ProcessKeys.owned?(:qb_ctx)
    assert ProcessKeys.owned?({:qb_prop_desc, 1, "a"})

    refute ProcessKeys.owned?(0)
    refute ProcessKeys.owned?(:not_quickbeam)
    refute ProcessKeys.owned?(QuickBEAM.VM.Heap)
    refute ProcessKeys.owned?({"qb_not_an_atom", 1})
  end

  test "Heap.reset removes registered heap keys only" do
    Process.put(:qb_ctx, :ctx)
    Process.put({:qb_prop_desc, 1, "a"}, :desc)
    Process.put(123, :object)
    Process.put(:not_quickbeam, :keep)

    assert Heap.reset() == :ok

    refute Process.get(:qb_ctx)
    refute Process.get({:qb_prop_desc, 1, "a"})
    refute Process.get(123)
    assert Process.get(:not_quickbeam) == :keep
  after
    Process.delete(:not_quickbeam)
  end
end
