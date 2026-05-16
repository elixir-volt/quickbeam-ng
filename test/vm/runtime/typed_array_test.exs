defmodule QuickBEAM.VM.Runtime.TypedArrayTest do
  use QuickBEAM.VMCase, async: true

  test "defineProperty treats integer-index keys beyond array-index range as typed-array indexes",
       %{
         rt: rt
       } do
    assert_modes(
      rt,
      ~S|let a = new Uint8Array(1); try { Object.defineProperty(a, "4294967295", {value: 1}); "ok"; } catch (e) { e.name; }|,
      "TypeError"
    )
  end
end
