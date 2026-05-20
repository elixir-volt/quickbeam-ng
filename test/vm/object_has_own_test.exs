defmodule QuickBEAM.VM.ObjectHasOwnTest do
  use ExUnit.Case, async: true

  @source ~S'''
  var obj = {};
  var sym = Symbol();
  var count = 0;
  var wrapper = {};
  wrapper[Symbol.toPrimitive] = function() {
    count += 1;
    return sym;
  };
  obj[sym] = 1;
  [Object.hasOwn(obj, wrapper), count];
  '''

  for mode <- [:beam, :beam_compiler] do
    @mode mode

    test "#{mode} Object.hasOwn uses ToPropertyKey for symbol-producing objects" do
      {:ok, runtime} = QuickBEAM.start(apis: false)
      assert {:ok, [true, 1]} = QuickBEAM.eval(runtime, @source, mode: @mode)
      QuickBEAM.stop(runtime)
    end
  end
end
