defmodule QuickBEAM.VM.Heap.ArgumentsTest do
  use QuickBEAM.VMCase, async: true

  test "sloppy arguments callee resolves to the current function", %{rt: rt} do
    assert beam!(rt, """
           (function () {
             return typeof arguments.callee;
           })();
           """) == "function"
  end
end
