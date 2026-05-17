defmodule QuickBEAM.VM.Runtime.IteratorTest do
  use QuickBEAM.VMCase, async: true

  test "for-of closes active iterator on thrown body", %{rt: rt} do
    assert beam!(
             rt,
             ~S|let closed=0; let it={ [Symbol.iterator](){return this}, next(){return {value:1,done:false}}, return(){closed=1; return {done:true}}}; try { for (let x of it) { throw new Error("x"); } } catch(e) {} closed|
           ) == 1
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
end
