defmodule QuickBEAM.VM.Compiler.DestructuringTest do
  use QuickBEAM.VMCase, async: true

  test "object rest binding copies non-excluded properties", %{rt: rt} do
    assert_modes(
      rt,
      ~S|var obj = {a: 1, b: 2}; var {a, ...rest} = obj; JSON.stringify(rest)|,
      ~S|{"b":2}|
    )
  end

  test "object rest binding skips getOwnPropertyDescriptor for computed and literal excluded keys",
       %{rt: rt} do
    code = """
    var excludedSymbol = Symbol("excluded_symbol");
    var includedSymbol = Symbol("included_symbol");
    var getOwnKeys = [];
    var proxy = new Proxy({}, {
      ownKeys() { return [excludedSymbol, "excludedString", "0", includedSymbol, "includedString", "1"]; },
      getOwnPropertyDescriptor(_target, key) { getOwnKeys.push(key); }
    });
    var {[excludedSymbol]: _, excludedString, 0: excludedIndex, ...rest} = proxy;
    getOwnKeys.map(key => key === includedSymbol ? "includedSymbol" : String(key)).join(",");
    """

    assert_modes(rt, code, "includedSymbol,includedString,1")
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
