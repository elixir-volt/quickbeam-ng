defmodule QuickBEAM.VM.ObjectModel.PrototypeTest do
  use QuickBEAM.VMCase, async: true

  test "array property lookup uses receiver-specific prototype", %{rt: rt} do
    assert_modes(rt, ~S|Object.setPrototypeOf([], { x: 1 })["x"]|, 1)
  end
end
