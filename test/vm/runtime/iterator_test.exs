defmodule QuickBEAM.VM.Runtime.IteratorTest do
  use QuickBEAM.VMCase, async: true

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
end
