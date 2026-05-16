defmodule QuickBEAM.VM.ObjectModel.DefineTest do
  use QuickBEAM.VMCase, async: true

  test "object literal fields define own data properties instead of invoking inherited setters",
       %{rt: rt} do
    assert_modes(
      rt,
      ~S|let proto = { set x(v) { throw "called"; } }; let obj = { __proto__: proto, x: 1 }; obj.x|,
      1
    )
  end
end
