defmodule QuickBEAM.VM.Runtime.DataViewTest do
  use QuickBEAM.VMCase, async: true

  test "BigInt setters reject Number values", %{rt: rt} do
    assert beam!(rt, """
           let view = new DataView(new ArrayBuffer(8));
           try { view.setBigInt64(0, 1); false; }
           catch (e) { e instanceof TypeError; }
           """) == true
  end

  test "ToIndex rejects coerced infinities", %{rt: rt} do
    assert beam!(
             rt,
             ~S|let view = new DataView(new ArrayBuffer(8)); try { view.getInt8("Infinity"); "ok"; } catch (e) { e.name; }|
           ) == "RangeError"
  end

  test "BigInt setters coerce Boolean and object values with ToBigInt", %{rt: rt} do
    assert beam!(
             rt,
             ~S|let view = new DataView(new ArrayBuffer(16)); view.setBigInt64(0, true); view.setBigInt64(8, { valueOf() { return 2n; } }); [view.getUint8(7), view.getUint8(15)].join(",")|
           ) == "1,2"
  end
end
