defmodule QuickBEAM.VM.Runtime.SymbolTest do
  use QuickBEAM.VMCase, async: true

  test "anonymous symbol has undefined description", %{rt: rt} do
    assert_modes(rt, ~S|Symbol().description === undefined|, true)
  end

  test "anonymous symbol names computed accessor with empty description", %{rt: rt} do
    assert_modes(
      rt,
      ~S|let sym = Symbol(); let obj = { get [sym]() {} }; Object.getOwnPropertyDescriptor(obj, sym).get.name|,
      "get "
    )
  end
end
