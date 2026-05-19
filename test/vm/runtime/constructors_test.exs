defmodule QuickBEAM.VM.Runtime.ConstructorsTest do
  use QuickBEAM.VM.TestCase, async: true

  test "core constructor prototypes are visible through generic builtin lookup", %{rt: rt} do
    assert_modes(
      rt,
      ~S<[typeof String.prototype, typeof Number.prototype, typeof Symbol.prototype, typeof BigInt.prototype].join("|")>,
      "object|object|object|object"
    )
  end
end
