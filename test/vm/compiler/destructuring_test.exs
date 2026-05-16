defmodule QuickBEAM.VM.Compiler.DestructuringTest do
  use QuickBEAM.VMCase, async: true

  test "object rest binding copies non-excluded properties", %{rt: rt} do
    assert_modes(
      rt,
      ~S|var obj = {a: 1, b: 2}; var {a, ...rest} = obj; JSON.stringify(rest)|,
      ~S|{"b":2}|
    )
  end

  test "object rest binding skips getOwnPropertyDescriptor for literal excluded keys", %{rt: rt} do
    code = """
    var calls = [];
    var proxy = new Proxy({}, {
      ownKeys() { return ["x", "a"]; },
      getOwnPropertyDescriptor(_target, key) { calls.push(key); }
    });
    var {x: _, ...rest} = proxy;
    calls.join(",");
    """

    assert_modes(rt, code, "a")
  end
end
