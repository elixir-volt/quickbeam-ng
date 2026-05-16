defmodule QuickBEAM.VM.ReviewRegressionTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, rt} = QuickBEAM.start()
    %{rt: rt}
  end

  defp beam!(rt, code) do
    assert {:ok, value} = QuickBEAM.eval(rt, code, mode: :beam)
    value
  end

  test "Set iteration visits delete-then-readd entries", %{rt: rt} do
    assert beam!(rt, """
           let set = new Set([1, 2]);
           let iterator = set.values();
           let values = [iterator.next().value];
           set.delete(2);
           set.add(2);
           values.push(iterator.next().value);
           values.join(',');
           """) == "1,2"
  end

  test "Set forEach visits delete-then-readd entries", %{rt: rt} do
    assert beam!(rt, """
           let set = new Set([1, 2]);
           let values = [];
           set.forEach(value => {
             values.push(value);
             if (value === 1) {
               set.delete(2);
               set.add(2);
             }
           });
           values.join(',');
           """) == "1,2"
  end

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

  test "unicode indices fallback does not count lookbehind as a capture", %{rt: rt} do
    assert beam!(rt, "/(?<=a)b/du.exec('ab').indices.length") == 1
  end

  test "String.fromCodePoint preserves surrogate code points", %{rt: rt} do
    assert beam!(rt, "String.fromCodePoint(0xD800) === ''") == false
  end

  test "sloppy arguments callee resolves to the current function", %{rt: rt} do
    assert beam!(rt, """
           (function () {
             return typeof arguments.callee;
           })();
           """) == "function"
  end

  test "Iterator.from wraps arbitrary self-iterables before helper validation", %{rt: rt} do
    assert beam!(rt, """
           let closed = 0;
           let iterator = {
             next() { return { done: true }; },
             return() { closed++; },
             [Symbol.iterator]() { return this; }
           };
           try { Iterator.from(iterator).map(1); } catch (e) {}
           closed;
           """) == 0
  end

  test "array spread rejects present non-callable iterator", %{rt: rt} do
    assert {:error, %QuickBEAM.JS.Error{name: "TypeError"}} =
             QuickBEAM.eval(rt, "[...{ [Symbol.iterator]: 1 }]", mode: :beam)
  end

  test "array spread uses JS truthiness for iterator done", %{rt: rt} do
    assert beam!(rt, """
           let calls = 0;
           let iterator = {
             next() {
               if (calls++) return { done: true };
               return { done: 0, value: 7 };
             }
           };
           let iterable = { [Symbol.iterator]() { return iterator; } };
           [...iterable][0];
           """) == 7
  end

  test "DataView BigInt setters reject Number values", %{rt: rt} do
    assert beam!(rt, """
           let view = new DataView(new ArrayBuffer(8));
           try { view.setBigInt64(0, 1); false; }
           catch (e) { e instanceof TypeError; }
           """) == true
  end
end
