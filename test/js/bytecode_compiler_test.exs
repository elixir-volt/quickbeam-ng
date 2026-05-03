defmodule QuickBEAM.JS.BytecodeCompilerTest do
  use ExUnit.Case, async: true

  alias QuickBEAM.JS.BytecodeCompiler
  alias QuickBEAM.VM.{Compiler, Heap, Interpreter}

  describe "compile/1" do
    test "compiles arithmetic expression scripts" do
      assert_compiles_to("1 + 2 * 3", 7)
    end

    test "compiles local declarations and reads" do
      assert_compiles_to("let x = 1; x + 2", 3)
    end

    test "compiles function declarations and direct calls" do
      assert_compiles_to("function f(a){ return a + 1; } f(2)", 3)
    end

    test "emits QuickJS-loadable bytecode binaries" do
      assert {:ok, binary} =
               BytecodeCompiler.compile_to_binary("function f(a){ return a + 1; } f(2)")

      assert {:ok, rt} = QuickBEAM.start(apis: false)

      try do
        assert {:ok, 3} = QuickBEAM.load_bytecode(rt, binary)
      after
        QuickBEAM.stop(rt)
      end
    end

    test "keeps the new frontend compiler separate from the VM compiler" do
      assert {:ok, bytecode} = BytecodeCompiler.compile("1 + 2")
      assert %QuickBEAM.VM.Bytecode{} = bytecode
      assert {:ok, 3} = Compiler.invoke(bytecode.value, [])
    end

    test "returns an explicit unsupported error for unresolved globals" do
      assert {:error, {:unsupported, {:unresolved_identifier, "missing"}}} =
               BytecodeCompiler.compile("missing")
    end
  end

  defp assert_compiles_to(source, expected) do
    Heap.reset()
    assert {:ok, bytecode} = BytecodeCompiler.compile(source)

    assert {:ok, ^expected} =
             Interpreter.eval(bytecode.value, [], %{gas: 1_000_000}, bytecode.atoms)

    assert {:ok, ^expected} = Compiler.invoke(bytecode.value, [])
  end
end
