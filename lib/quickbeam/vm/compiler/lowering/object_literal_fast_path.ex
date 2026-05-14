defmodule QuickBEAM.VM.Compiler.Lowering.ObjectLiteralFastPath do
  @moduledoc "Fast-path lowering for object literals with statically known data fields."

  import QuickBEAM.VM.OpcodeFamily, only: [is_small_int_push: 1]

  alias QuickBEAM.VM.Compiler.Analysis.CFG
  alias QuickBEAM.VM.Compiler.Lowering.{Builder, Literals, State}
  alias QuickBEAM.VM.OpcodeFamily

  @line 1

  @doc "Attempts to lower an object literal followed by define_field opcodes."
  def try_lower(instructions, size, idx, arg_count, state) do
    with {:ok, map_pairs, skip_to, state} <-
           collect_define_fields(instructions, size, idx + 1, arg_count, state) do
      keys_list = Enum.map(map_pairs, &elem(&1, 0))
      vals_list = Enum.map(map_pairs, &elem(&1, 1))
      keys_tuple = {:tuple, @line, keys_list}
      vals_tuple = {:tuple, @line, vals_list}

      ct_offsets =
        map_pairs
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {{key_expr, _value_expr}, field_idx}, acc ->
          case Literals.string_lossy(key_expr) do
            key when is_binary(key) -> Map.put(acc, key, field_idx)
            _ -> acc
          end
        end)

      value_map =
        Map.new(map_pairs, fn {key_expr, value_expr} ->
          {Literals.string_lossy(key_expr), value_expr}
        end)

      {obj, state} =
        State.bind(
          state,
          Builder.temp_name(state.temp),
          Builder.remote_call(QuickBEAM.VM.Heap, :wrap_keyed, [keys_tuple, vals_tuple])
        )

      {:ok, State.push(state, obj, {:shaped_object, ct_offsets, value_map}), skip_to}
    end
  end

  defp collect_define_fields(instructions, size, idx, arg_count, state) do
    collect_define_fields(instructions, size, idx, arg_count, state, [])
  end

  defp collect_define_fields(_instructions, size, idx, _arg_count, state, acc)
       when idx + 1 >= size do
    if acc == [], do: :not_literal, else: {:ok, Enum.reverse(acc), idx, state}
  end

  defp collect_define_fields(instructions, size, idx, arg_count, state, acc) do
    val_instr = elem(instructions, idx)
    df_instr = elem(instructions, idx + 1)

    with {val_op, val_args} <- val_instr,
         {df_op, [key_idx]} <- df_instr,
         {:ok, :define_field} <- CFG.opcode_name(df_op),
         {:ok, val_expr, new_state} <- lower_value_opcode(val_op, val_args, arg_count, state) do
      key_name = Builder.atom_name(new_state, key_idx)

      if is_binary(key_name) do
        key_expr = Builder.literal(key_name)

        collect_define_fields(instructions, size, idx + 2, arg_count, new_state, [
          {key_expr, val_expr} | acc
        ])
      else
        if acc == [], do: :not_literal, else: {:ok, Enum.reverse(acc), idx, state}
      end
    else
      _ ->
        if acc == [], do: :not_literal, else: {:ok, Enum.reverse(acc), idx, state}
    end
  end

  defp lower_value_opcode(op, args, _arg_count, state) do
    case CFG.opcode_name(op) do
      {:ok, name} when name in [:push_i32, :push_i16, :push_i8] ->
        {:ok, Builder.integer(hd(args)), state}

      {:ok, name} when is_small_int_push(name) ->
        {:ok, value} = OpcodeFamily.small_int_push(name)
        {:ok, Builder.integer(value), state}

      {:ok, :null} ->
        {:ok, Builder.atom(nil), state}

      {:ok, :undefined} ->
        {:ok, Builder.atom(:undefined), state}

      {:ok, :push_false} ->
        {:ok, Builder.atom(false), state}

      {:ok, :push_true} ->
        {:ok, Builder.atom(true), state}

      {:ok, :push_empty_string} ->
        {:ok, Builder.literal(""), state}

      {:ok, name} when name in [:get_arg, :get_arg0, :get_arg1, :get_arg2, :get_arg3] ->
        {:ok, State.slot_expr(state, compact_slot_index(name, args)), state}

      {:ok, name} when name in [:get_loc, :get_loc0, :get_loc1, :get_loc2, :get_loc3] ->
        {:ok, State.slot_expr(state, compact_slot_index(name, args)), state}

      {:ok, :push_atom_value} ->
        {:ok, State.compiler_call(state, :push_atom_value, [Builder.literal(hd(args))]), state}

      _ ->
        :error
    end
  end

  defp compact_slot_index(_op, [idx | _]), do: idx
  defp compact_slot_index(:get_arg0, []), do: 0
  defp compact_slot_index(:get_arg1, []), do: 1
  defp compact_slot_index(:get_arg2, []), do: 2
  defp compact_slot_index(:get_arg3, []), do: 3
  defp compact_slot_index(:get_loc0, []), do: 0
  defp compact_slot_index(:get_loc1, []), do: 1
  defp compact_slot_index(:get_loc2, []), do: 2
  defp compact_slot_index(:get_loc3, []), do: 3
end
