defmodule QuickBEAM.VM.Compiler.RuntimeHelpers.Errors do
  @moduledoc "Error construction and compiled stack formatting for BEAM-compiled JavaScript."

  alias QuickBEAM.VM.{Heap, RuntimeState, SourcePosition}
  alias QuickBEAM.VM.Compiler.RuntimeHelpers.Context, as: RuntimeContext
  alias QuickBEAM.VM.ObjectModel.Get

  def throw(ctx, atom_idx, reason, atoms_resolver) do
    name = atoms_resolver.(ctx, atom_idx)
    {error_type, message} = message(name, reason)
    throw({:js_throw, Heap.make_error(message, error_type)})
  end

  def message(name, reason) do
    case reason do
      0 -> {"TypeError", "'#{name}' is read-only"}
      1 -> {"SyntaxError", "redeclaration of '#{name}'"}
      2 -> {"ReferenceError", "cannot access '#{name}' before initialization"}
      3 -> {"ReferenceError", "unsupported reference to 'super'"}
      4 -> {"TypeError", "iterator does not have a throw method"}
      _ -> {"Error", name}
    end
  end

  def make_error_with_ctx(ctx, message, name, stack_override \\ nil) do
    RuntimeState.with_context(RuntimeContext.ensure(ctx), fn ->
      Heap.make_error(message, name)
      |> ensure_compiled_stack(ctx, stack_override)
    end)
  end

  def compiled_stack(ctx) do
    case RuntimeContext.current_func(ctx) do
      %QuickBEAM.VM.Function{} = fun ->
        "    at #{fun.filename}:#{fun.line_num}:#{fun.col_num}"

      {:closure, _captures, %QuickBEAM.VM.Function{} = fun} ->
        "    at #{fun.filename}:#{fun.line_num}:#{fun.col_num}"

      _ ->
        ""
    end
  end

  def compiled_stack(ctx, pc) do
    case RuntimeContext.current_func(ctx) do
      %QuickBEAM.VM.Function{} = fun -> stack_for_pc(fun, pc)
      {:closure, _captures, %QuickBEAM.VM.Function{} = fun} -> stack_for_pc(fun, pc)
      _ -> ""
    end
  end

  defp ensure_compiled_stack({:obj, ref} = error, ctx, stack_override) do
    stack = stack_override || compiled_stack(ctx)

    case Get.get(error, "stack") do
      "" ->
        Heap.update_obj(ref, %{}, &Map.put(&1, "stack", stack))
        error

      _ when stack_override != nil ->
        Heap.update_obj(ref, %{}, &Map.put(&1, "stack", stack))
        error

      _ ->
        error
    end
  end

  defp stack_for_pc(%QuickBEAM.VM.Function{} = fun, pc) do
    {line, col} = SourcePosition.source_position(fun, pc)
    "    at #{fun.filename}:#{line}:#{col}"
  end
end
