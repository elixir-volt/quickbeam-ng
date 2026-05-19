defmodule QuickBEAM.VM.Compiler.RuntimeHelpers.Errors do
  @moduledoc "Error construction and compiled stack formatting for BEAM-compiled JavaScript."

  alias QuickBEAM.VM.{GlobalEnvironment, Heap, SourcePosition}
  alias QuickBEAM.VM.Interpreter.Context
  alias QuickBEAM.VM.ObjectModel.Get

  def throw_error(ctx, atom_idx, reason, atoms_resolver) do
    name = atoms_resolver.(ctx, atom_idx)
    {error_type, message} = throw_error_message(name, reason)
    throw({:js_throw, Heap.make_error(message, error_type)})
  end

  def throw_error_message(name, reason) do
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
    previous_ctx = Heap.get_ctx()
    Heap.put_ctx(ensure_context(ctx))

    try do
      Heap.make_error(message, name)
      |> ensure_compiled_stack(ctx, stack_override)
    after
      if previous_ctx, do: Heap.put_ctx(previous_ctx), else: Heap.put_ctx(nil)
    end
  end

  def compiled_stack(ctx) do
    case context_current_func(ctx) do
      %QuickBEAM.VM.Function{} = fun ->
        "    at #{fun.filename}:#{fun.line_num}:#{fun.col_num}"

      {:closure, _captures, %QuickBEAM.VM.Function{} = fun} ->
        "    at #{fun.filename}:#{fun.line_num}:#{fun.col_num}"

      _ ->
        ""
    end
  end

  def compiled_stack(ctx, pc) do
    case context_current_func(ctx) do
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

  defp context_current_func(%{current_func: current_func}), do: current_func
  defp context_current_func(_), do: :undefined

  defp ensure_context(%Context{} = ctx), do: ctx

  defp ensure_context(map) when is_map(map) do
    struct(Context, Map.merge(Map.from_struct(%Context{}), map))
  end

  defp ensure_context(_),
    do: %Context{atoms: Heap.get_atoms(), globals: GlobalEnvironment.base_globals()}
end
