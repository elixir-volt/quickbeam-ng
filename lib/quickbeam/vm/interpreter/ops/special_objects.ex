defmodule QuickBEAM.VM.Interpreter.Ops.SpecialObjects do
  @moduledoc "Interpreter helpers for QuickJS special-object bytecodes."

  alias QuickBEAM.VM.{Heap, RuntimeState}
  alias QuickBEAM.VM.Interpreter.{Context, Frame}
  alias QuickBEAM.VM.Semantics.Construction

  require Frame

  def build(type, frame, %Context{} = ctx) do
    %Context{arg_buf: arg_buf, current_func: current_func, home_object: home_object} = ctx

    value =
      case type do
        type when type in [0, 1] ->
          arguments_object(ctx, frame, arg_buf, current_func)

        _ ->
          Construction.special_object(type, current_func, arg_buf, ctx.new_target, home_object)
      end

    ctx =
      if type in [0, 1] do
        %{
          ctx
          | globals:
              Map.put(
                ctx.globals,
                RuntimeState.arguments_object_key(current_func, arg_buf),
                value
              )
        }
      else
        ctx
      end

    {value, ctx}
  end

  defp arguments_object(ctx, frame, arg_buf, current_func) do
    key = RuntimeState.arguments_object_key(current_func, arg_buf)

    case Map.fetch(ctx.globals, key) do
      {:ok, arguments} -> arguments
      :error -> cached_arguments_object(ctx, frame, arg_buf, current_func, key)
    end
  end

  defp cached_arguments_object(ctx, frame, arg_buf, current_func, key) do
    case RuntimeState.get_arguments_object(key) do
      nil ->
        arguments =
          Heap.wrap_arguments(Tuple.to_list(arg_buf),
            strict: QuickBEAM.VM.Value.strict_context?(ctx),
            callee: current_func,
            mapped: mapped_argument_cells(ctx, frame)
          )

        RuntimeState.put_arguments_object(key, arguments)

      arguments ->
        arguments
    end
  end

  defp mapped_argument_cells(ctx, frame) do
    if mapped_arguments?(ctx) do
      locals = function_locals(ctx)
      closure_ref_count = closure_ref_count(ctx)
      var_refs = elem(frame, Frame.var_refs())
      count = min(tuple_size(ctx.arg_buf), length(locals))

      if count == 0 do
        %{}
      else
        last_parameter_index = last_parameter_index_by_var_ref(locals, count)

        0..(count - 1)//1
        |> Enum.reduce(%{}, fn index, acc ->
          mapped_argument_cell(
            locals,
            var_refs,
            closure_ref_count,
            last_parameter_index,
            index,
            acc
          )
        end)
      end
    else
      %{}
    end
  end

  defp mapped_argument_cell(locals, var_refs, closure_ref_count, last_parameter_index, index, acc) do
    case Enum.at(locals, index) do
      %{var_ref_idx: ref_idx}
      when is_integer(ref_idx) and closure_ref_count + ref_idx < tuple_size(var_refs) ->
        if Map.get(last_parameter_index, ref_idx) == index do
          case elem(var_refs, closure_ref_count + ref_idx) do
            {:cell, _} = cell -> Map.put(acc, index, cell)
            _ -> acc
          end
        else
          acc
        end

      _ ->
        acc
    end
  end

  defp last_parameter_index_by_var_ref(locals, count) do
    0..(count - 1)//1
    |> Enum.reduce(%{}, fn index, acc ->
      case Enum.at(locals, index) do
        %{var_ref_idx: ref_idx} when is_integer(ref_idx) -> Map.put(acc, ref_idx, index)
        _ -> acc
      end
    end)
  end

  defp mapped_arguments?(ctx) do
    case ctx.current_func do
      {:closure, _, %QuickBEAM.VM.Function{} = fun} ->
        not fun.is_strict_mode and fun.has_simple_parameter_list

      %QuickBEAM.VM.Function{} = fun ->
        not fun.is_strict_mode and fun.has_simple_parameter_list

      _ ->
        false
    end
  end

  defp function_locals(ctx) do
    case ctx.current_func do
      {:closure, _, %QuickBEAM.VM.Function{locals: locals}} -> locals
      %QuickBEAM.VM.Function{locals: locals} -> locals
      _ -> []
    end
  end

  defp closure_ref_count(ctx) do
    case ctx.current_func do
      {:closure, captured, _} when is_map(captured) -> map_size(captured)
      _ -> 0
    end
  end
end
