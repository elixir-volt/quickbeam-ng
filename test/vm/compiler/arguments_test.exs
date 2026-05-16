defmodule QuickBEAM.VM.Compiler.ArgumentsTest do
  use QuickBEAM.VMCase, async: true

  test "compiled arguments object is iterable in spread and for-of", %{rt: rt} do
    assert compiler!(rt, "function f(){ return [...arguments].join(','); } f(1,2,3)") == "1,2,3"

    assert compiler!(
             rt,
             "function f(){ let r=[]; for (let x of arguments) r.push(x); return r.join(','); } f(1,2,3)"
           ) == "1,2,3"
  end
end
