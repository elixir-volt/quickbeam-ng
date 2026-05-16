defmodule QuickBEAM.VM.Runtime.RegExpTest do
  use QuickBEAM.VMCase, async: true

  test "unicode indices fallback does not count lookbehind as a capture", %{rt: rt} do
    assert beam!(rt, "/(?<=a)b/du.exec('ab').indices.length") == 1
  end
end
