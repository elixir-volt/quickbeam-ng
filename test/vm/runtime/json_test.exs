defmodule QuickBEAM.VM.Runtime.JSONTest do
  use QuickBEAM.VMCase, async: true

  test "array stringify reads elements through property access", %{rt: rt} do
    assert_modes(
      rt,
      ~S|let a = [1]; Object.defineProperty(a, "0", { get() { return 2; }, enumerable: true }); JSON.stringify(a)|,
      "[2]"
    )
  end

  test "array stringify reads inherited indexed properties for holes", %{rt: rt} do
    assert_modes(
      rt,
      ~S|let a = [,]; Object.setPrototypeOf(a, {0: 7}); JSON.stringify(a)|,
      "[7]"
    )
  end
end
