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

      # ── Objects ──

      defp run({@op_object, []}, pc, frame, stack, gas, ctx) do
        run(pc + 1, frame, [Construction.new_object() | stack], gas, ctx)
      end

      defp run({@op_get_field, [atom_idx]}, __pc, frame, [obj | _rest], gas, ctx)
           when is_nullish(obj) do
        throw_null_property_error(frame, obj, atom_idx, gas, ctx)
      end

      defp run({@op_get_field, [atom_idx]}, pc, frame, [obj | rest], gas, ctx) do
        run(
          pc + 1,
          frame,
          [Get.get(obj, Names.resolve_atom(ctx, atom_idx)) | rest],
          gas,
          ctx
        )
      end

      defp run({@op_put_field, [atom_idx]}, pc, frame, [val, obj | rest], gas, ctx) do
        name = Names.resolve_atom(ctx, atom_idx)

        result =
          try do
            PropertyAccess.set_property(ctx, obj, name, val)
            :ok
          catch
            {:js_throw, error} -> {:throw, error}
          end

        case result do
          :ok ->
            ctx =
              if QuickBEAM.VM.Execution.SetterState.invoked?(),
                do: ctx,
                else: sync_global_this_write(ctx, obj, name, val)

            ctx = refresh_persistent_globals(ctx)
            frame = sync_setter_globals_to_frame(frame, ctx)
            run(pc + 1, frame, rest, gas, ctx)

          {:throw, error} ->
            throw_or_catch(frame, error, gas, close_active_iterators_on_abrupt(rest, ctx))
        end
      end

      defp run({@op_define_field, [atom_idx]}, pc, frame, [val, obj | rest], gas, ctx) do
        try do
          Put.define_array_el(obj, Names.resolve_atom(ctx, atom_idx), val)
          run(pc + 1, frame, [obj | rest], gas, ctx)
        catch
          {:js_throw, error} ->
            ctx = RuntimeState.current() || ctx
            throw_or_catch(frame, error, gas, ctx)
        end
      end

      defp run({@op_get_array_el, []}, pc, frame, [idx, obj | rest], gas, ctx) do
        try do
          run(pc + 1, frame, [PropertyAccess.get_property(obj, idx) | rest], gas, ctx)
        catch
          {:js_throw, error} ->
            ctx = RuntimeState.current() || ctx
            throw_or_catch(frame, error, gas, ctx)
        end
      end

      defp run({@op_put_array_el, []}, pc, frame, [val, idx, obj | rest], gas, ctx) do
        try do
          PropertyAccess.set_property(ctx, obj, idx, val)

          ctx =
            case Heap.get_persistent_globals() do
              nil -> ctx
              p when map_size(p) == 0 -> ctx
              p -> Context.mark_dirty(%{ctx | globals: Map.merge(ctx.globals, p)})
            end

          frame = sync_setter_globals_to_frame(frame, ctx)
          run(pc + 1, frame, rest, gas, ctx)
        catch
          {:js_throw, error} ->
            ctx = RuntimeState.current() || ctx
            throw_or_catch(frame, error, gas, close_active_iterators_on_abrupt(rest, ctx))
        end
      end

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

      defp run({@op_get_length, []}, pc, frame, [obj | rest], gas, ctx) do
        run(pc + 1, frame, [Get.length_of(obj) | rest], gas, ctx)
      end

      defp run({@op_array_from, [argc]}, pc, frame, stack, gas, ctx) do
        {elems, rest} = Enum.split(stack, argc)
        values = Enum.reverse(elems)
        run(pc + 1, frame, [ObjectLiterals.array_from(values) | rest], gas, ctx)
      end

      defp run({@op_get_field2, [atom_idx]}, __pc, frame, [obj | _rest], gas, ctx)
           when is_nullish(obj) do
        throw_null_property_error(frame, obj, atom_idx, gas, ctx)
      end

      defp run({@op_get_field2, [atom_idx]}, pc, frame, [obj | rest], gas, ctx) do
        val = Get.get(obj, Names.resolve_atom(ctx, atom_idx))
        run(pc + 1, frame, [val, obj | rest], gas, ctx)
      end

      # ── Array element access (2-element push) ──

      defp run({@op_get_array_el2, []}, pc, frame, [idx, obj | rest], gas, ctx) do
        try do
          run(pc + 1, frame, [PropertyAccess.get_property(obj, idx), obj | rest], gas, ctx)
        catch
          {:js_throw, error} ->
            ctx = RuntimeState.current() || ctx
            throw_or_catch(frame, error, gas, ctx)
        end
      end

      # ── Misc / no-op ──

      defp run({@op_nop, []}, pc, frame, stack, gas, ctx),
        do: run(pc + 1, frame, stack, gas, ctx)

      defp run({@op_to_object, []}, _pc, frame, [nil | _rest], gas, ctx) do
        throw_or_catch(
          frame,
          Heap.make_error("Cannot convert null to object", "TypeError"),
          gas,
          ctx
        )
      end

      defp run({@op_to_object, []}, _pc, frame, [:undefined | _rest], gas, ctx) do
        throw_or_catch(
          frame,
          Heap.make_error("Cannot convert undefined to object", "TypeError"),
          gas,
          ctx
        )
      end

      defp run({@op_to_object, []}, pc, frame, stack, gas, ctx),
        do: run(pc + 1, frame, stack, gas, ctx)

      defp run({@op_to_propkey, []}, pc, frame, [key | rest], gas, ctx) do
        case PropertyKeys.to_property_key(key, ctx) do
          {:ok, prop_key, ctx} -> run(pc + 1, frame, [prop_key | rest], gas, ctx)
          {:throw, error, ctx} -> throw_or_catch(frame, error, gas, ctx)
        end
      end

      defp run({@op_to_propkey2, []}, pc, frame, [key, obj | rest], gas, ctx) do
        try do
          prop_key = PropertyAccess.to_property_key_for_access(obj, key)

          run(
            pc + 1,
            frame,
            [prop_key, obj | rest],
            gas,
            GlobalEnvironment.refresh(RuntimeState.current() || ctx)
          )
        catch
          {:js_throw, error} -> throw_or_catch(frame, error, gas, RuntimeState.current() || ctx)
        end
      end

      defp run({@op_check_ctor, []}, pc, frame, stack, gas, ctx),
        do: run(pc + 1, frame, stack, gas, ctx)

      defp run({@op_check_ctor_return, []}, pc, frame, [val | rest], gas, ctx) do
        case Construction.check_ctor_return(val) do
          {:ok, replace_with_this?, checked_val} ->
            run(pc + 1, frame, [replace_with_this?, checked_val | rest], gas, ctx)

          {:error, message} ->
            throw_or_catch(frame, Heap.make_error(message, "TypeError"), gas, ctx)
        end
      end

      defp run({@op_set_name, [atom_idx]}, pc, frame, [fun | rest], gas, ctx) do
        named = Functions.set_name_atom(fun, atom_idx, ctx.atoms)
        run(pc + 1, frame, [named | rest], gas, ctx)
      end

      defp run({@op_invalid, []}, _pc, _frame, _stack, _gas, _ctx),
        do: throw({:error, :invalid_opcode})

      # ── Misc stubs ──

      defp run({@op_set_home_object, []}, pc, frame, [method, target | _] = stack, gas, ctx) do
        Functions.put_home_object(method, target)
        run(pc + 1, frame, stack, gas, ctx)
      end

      defp run({@op_set_proto, []}, pc, frame, [proto, obj | rest], gas, ctx) do
        case obj do
          {:obj, ref} ->
            map = Heap.get_obj(ref, %{})

            if is_map(map) and (is_object(proto) or proto == nil) do
              Heap.put_obj(ref, Map.put(map, proto(), proto))
            end

          _ ->
            :ok
        end

        run(pc + 1, frame, [obj | rest], gas, ctx)
      end

      defp run({@op_special_object, [type]}, pc, frame, stack, gas, %Context{} = ctx) do
        {val, ctx} = SpecialObjects.build(type, frame, ctx)
        run(pc + 1, frame, [val | stack], gas, ctx)
      end

      defp run({@op_set_name_computed, []}, pc, frame, [fun, name_val | rest], gas, ctx) do
        named = Functions.set_name_computed(fun, name_val)
        run(pc + 1, frame, [named, name_val | rest], gas, ctx)
      end

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

      defp run({@op_private_symbol, [atom_idx]}, pc, frame, stack, gas, ctx) do
        name = Names.resolve_atom(ctx, atom_idx)
        run(pc + 1, frame, [PrivateFields.symbol(name) | stack], gas, ctx)
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

      # ── regexp literal ──

      defp run({@op_regexp, []}, pc, frame, [pattern, flags | rest], gas, ctx) do
        run(pc + 1, frame, [{:regexp, pattern, flags, make_ref()} | rest], gas, ctx)
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
