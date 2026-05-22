defmodule QuickBEAM.VM.Interpreter.Ops.Objects do
  @moduledoc "Remaining object-adjacent opcode handlers pending focused extraction."

  defmacro __using__(_opts) do
    quote location: :keep do
      import QuickBEAM.VM.Value, only: [is_nullish: 1]

      alias QuickBEAM.VM.Heap
      alias QuickBEAM.VM.Interpreter.Ops.CopyDataProperties, as: CopyOp
      alias QuickBEAM.VM.Interpreter.Ops.Delete, as: DeleteOp
      alias QuickBEAM.VM.Interpreter.Ops.{InOperator, InstanceOf}

      defp run({@op_copy_data_properties, []}, pc, frame, [source, target | rest], gas, ctx) do
        case CopyOp.copy(target, source, ctx) do
          {:ok, ctx} -> run(pc + 1, frame, [source, target | rest], gas, ctx)
          {:throw, error, ctx} -> throw_or_catch(frame, error, gas, ctx)
        end
      end

      defp run({@op_instanceof, []}, pc, frame, [ctor, obj | rest], gas, ctx) do
        catch_and_dispatch(
          pc,
          frame,
          rest,
          gas,
          ctx,
          fn -> InstanceOf.evaluate(obj, ctor) end,
          true
        )
      end

      defp run({@op_delete, []}, __pc, frame, [key, obj | _rest], gas, ctx)
           when is_nullish(obj) do
        throw_or_catch(frame, DeleteOp.nullish_error(obj, key), gas, ctx)
      end

      defp run({@op_delete, []}, pc, frame, [key, obj | rest], gas, ctx) do
        result = DeleteOp.property(obj, key)

        if result == false and current_strict_mode?(ctx) do
          throw_or_catch(frame, Heap.make_error("Cannot delete property", "TypeError"), gas, ctx)
        else
          run(pc + 1, frame, [result | rest], gas, ctx)
        end
      end

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

      defp run({@op_copy_data_properties, [mask]}, pc, frame, stack, gas, ctx) do
        case CopyOp.copy_masked(stack, mask, ctx) do
          {:ok, ctx} -> run(pc + 1, frame, stack, gas, ctx)
          {:throw, error, ctx} -> throw_or_catch(frame, error, gas, ctx)
        end
      end
    end
  end
end
