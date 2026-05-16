defmodule QuickBEAM.VM.Runtime.StringTest do
  use QuickBEAM.VMCase, async: true

  test "custom global RegExp exec replaces all matches", %{rt: rt} do
    assert beam!(rt, """
           let regexp = /a/g;
           regexp.exec = function (string) {
             let index = string.indexOf('a', this.lastIndex);
             if (index < 0) return null;
             this.lastIndex = index + 1;
             return Object.assign(['a'], { index, input: string });
           };
           'aba'.replace(regexp, 'x');
           """) == "xbx"
  end

  test "named replacements use actual named capture numbering", %{rt: rt} do
    assert beam!(rt, "'ab'.replace(/(a)(?<b>b)/, '$<b>')") == "b"
  end

  test "fromCodePoint preserves surrogate code points", %{rt: rt} do
    assert beam!(rt, "String.fromCodePoint(0xD800) === ''") == false
  end
end
