defmodule QuickBEAM.VM.Runtime.DataViewTest do
  use QuickBEAM.VMCase, async: true

  test "BigInt setters reject Number values", %{rt: rt} do
    assert beam!(rt, """
           let view = new DataView(new ArrayBuffer(8));
           try { view.setBigInt64(0, 1); false; }
           catch (e) { e instanceof TypeError; }
           """) == true
  end
end
