defmodule QuickBEAM.VM.Interpreter.Ops.InOperatorAdapter do
  @moduledoc "in-operator opcode handler."

  defmacro __using__(_opts) do
    quote location: :keep do
      alias QuickBEAM.VM.Interpreter.Ops.InOperator

      defp run({@op_in, []}, pc, frame, [obj, key | rest], gas, ctx) do
        catch_and_dispatch(
          pc,
          frame,
          rest,
          gas,
          ctx,
          fn -> InOperator.evaluate(key, obj) end,
          false
        )
      end
    end
  end
end
