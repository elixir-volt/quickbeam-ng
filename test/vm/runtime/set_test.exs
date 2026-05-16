defmodule QuickBEAM.VM.Runtime.SetTest do
  use QuickBEAM.VMCase, async: true

  test "iteration visits delete-then-readd entries", %{rt: rt} do
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

  test "forEach visits delete-then-readd entries", %{rt: rt} do
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
end
