defmodule QuickBEAM.VM.Compiler.RuntimeABITest do
  use ExUnit.Case, async: true

  alias QuickBEAM.VM.Compiler.RuntimeABI
  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.Interpreter.Context

  setup do
    Heap.reset()
    :ok
  end

  test "get_field resolves atom keys from supplied context" do
    Heap.put_atoms({"ambient"})
    object = Heap.wrap(%{"actual" => 7, "ambient" => 9})
    ctx = %Context{atoms: {"actual"}}

    assert RuntimeABI.get_field(ctx, object, 0) == 7
  end
end
