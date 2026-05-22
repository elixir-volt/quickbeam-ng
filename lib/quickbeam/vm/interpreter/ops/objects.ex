defmodule QuickBEAM.VM.Interpreter.Ops.Objects do
  @moduledoc "Object creation, field access, array element access, and misc object stubs."

  @doc "Installs the Object creation, field access, array element access, and misc object stubs helpers into the caller module."
  defmacro __using__(_opts) do
    quote location: :keep do
      import QuickBEAM.VM.Value, only: [is_object: 1, is_nullish: 1]

      alias QuickBEAM.VM.{
        Builtin,
        GlobalEnvironment,
        Heap,
        Names,
        RuntimeState,
        Value
      }

      alias QuickBEAM.VM.Interpreter.Context
      alias QuickBEAM.VM.Interpreter.Ops.CopyDataProperties, as: CopyOp
      alias QuickBEAM.VM.Interpreter.Ops.Delete, as: DeleteOp

      alias QuickBEAM.VM.Interpreter.Ops.{
        InOperator,
        InstanceOf,
        ObjectLiterals,
        PrivateFields,
        PropertyKeys,
        SpecialObjects,
        SuperProperties
      }

      alias QuickBEAM.VM.ObjectModel.{
        Delete,
        Functions,
        Get,
        Put
      }

      alias QuickBEAM.VM.Semantics.{Construction, PropertyAccess}

      defp run({@op_get_super_value, []}, pc, frame, [key, proto, this_obj | rest], gas, ctx) do
        val = SuperProperties.get_value(proto, this_obj, key)
        run(pc + 1, frame, [val | rest], gas, ctx)
      end

      defp run(
             {@op_put_super_value, []},
             pc,
             frame,
             [val, key, proto_obj, this_obj | rest],
             gas,
             ctx
           ) do
        try do
          SuperProperties.put_value(proto_obj, this_obj, key, val)
          run(pc + 1, frame, rest, gas, ctx)
        catch
          {:js_throw, error} ->
            ctx = RuntimeState.current() || ctx
            throw_or_catch(frame, error, gas, ctx)
        end
      end

      defp run({@op_get_private_field, []}, pc, frame, [key, obj | rest], gas, ctx) do
        case PrivateFields.get(obj, key) do
          {:ok, val} -> run(pc + 1, frame, [val | rest], gas, ctx)
          {:throw, error} -> throw_or_catch(frame, error, gas, ctx)
        end
      end

      defp run({@op_put_private_field, []}, pc, frame, [key, val, obj | rest], gas, ctx) do
        case PrivateFields.put(obj, key, val) do
          :ok -> run(pc + 1, frame, rest, gas, ctx)
          {:throw, error} -> throw_or_catch(frame, error, gas, ctx)
        end
      end

      defp run({@op_define_private_field, []}, pc, frame, [val, key, obj | rest], gas, ctx) do
        case PrivateFields.define(obj, key, val) do
          :ok -> run(pc + 1, frame, rest, gas, ctx)
          {:throw, error} -> throw_or_catch(frame, error, gas, ctx)
        end
      end

      defp run({@op_private_in, []}, pc, frame, [key, obj | rest], gas, ctx) do
        run(pc + 1, frame, [PrivateFields.has?(obj, key) | rest], gas, ctx)
      end

      # ── Misc / no-op ──

      defp run({@op_nop, []}, pc, frame, stack, gas, ctx),
        do: run(pc + 1, frame, stack, gas, ctx)

      defp run({@op_invalid, []}, _pc, _frame, _stack, _gas, _ctx),
        do: throw({:error, :invalid_opcode})

      # ── Misc stubs ──

      defp run({@op_copy_data_properties, []}, pc, frame, [source, target | rest], gas, ctx) do
        case CopyOp.copy(target, source, ctx) do
          {:ok, ctx} -> run(pc + 1, frame, [source, target | rest], gas, ctx)
          {:throw, error, ctx} -> throw_or_catch(frame, error, gas, ctx)
        end
      end

      defp run(
             {@op_get_super, []},
             pc,
             frame,
             [func | rest],
             gas,
             %Context{home_object: home_object, super: super} = ctx
           ) do
        val = SuperProperties.get(func, home_object, super)
        run(pc + 1, frame, [val | rest], gas, ctx)
      end

      # ── instanceof ──

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

      # ── delete ──

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

      @non_configurable_globals MapSet.new(~w(NaN undefined Infinity globalThis))

      defp run({@op_delete_var, [atom_idx]}, pc, frame, stack, gas, ctx) do
        name = Names.resolve_atom(ctx.atoms, atom_idx)
        builtins = Heap.get_builtin_names() || MapSet.new()

        result =
          case Map.fetch(ctx.globals, name) do
            {:ok, _} ->
              if MapSet.member?(@non_configurable_globals, name) do
                false
              else
                MapSet.member?(builtins, name)
              end

            :error ->
              true
          end

        run(pc + 1, frame, [result | stack], gas, ctx)
      end

      # ── in operator ──

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

      # ── Object spread (copy_data_properties with mask) ──

      defp run({@op_copy_data_properties, [mask]}, pc, frame, stack, gas, ctx) do
        case CopyOp.copy_masked(stack, mask, ctx) do
          {:ok, ctx} -> run(pc + 1, frame, stack, gas, ctx)
          {:throw, error, ctx} -> throw_or_catch(frame, error, gas, ctx)
        end
      end
    end
  end
end
