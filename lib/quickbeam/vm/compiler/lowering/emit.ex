defmodule QuickBEAM.VM.Compiler.Lowering.Emit do
  @moduledoc "Operand-stack and body-emission helpers for compiler lowering state."

  alias QuickBEAM.VM.Compiler.Lowering.{Builder, Types}

  @doc "Prepends one Erlang abstract-form expression to the accumulated body."
  def emit(state, expr), do: %{state | body: [expr | state.body]}

  def emit_all(state, exprs), do: %{state | body: Enum.reverse(exprs, state.body)}

  def bind(state, name, expr) do
    var = Builder.var(name)
    {var, %{state | body: [Builder.match(var, expr) | state.body], temp: state.temp + 1}}
  end

  @doc "Pushes an expression and optional type onto the lowering operand stack."
  def push(state, expr), do: push(state, expr, Types.infer_expr_type(expr))

  def push(state, expr, type),
    do: %{state | stack: [expr | state.stack], stack_types: [type | state.stack_types]}

  @doc "Pushes several expressions onto the lowering operand stack in stack order."
  def push_many(state, exprs, types) when length(exprs) == length(types),
    do: %{state | stack: exprs ++ state.stack, stack_types: types ++ state.stack_types}

  @doc "Binds a runtime call that returns a tuple and pushes selected tuple elements."
  def bind_pair(state, name, call, types) do
    {pair, state} = bind(state, name, call)
    elements = Enum.map(1..length(types), &Builder.tuple_element(pair, &1))
    push_many(state, elements, types)
  end

  def pop_typed(%{stack: [expr | rest], stack_types: [type | type_rest]} = state),
    do: {:ok, expr, type, %{state | stack: rest, stack_types: type_rest}}

  def pop_typed(_state), do: {:error, :stack_underflow}

  def pop(%{stack: [expr | rest], stack_types: [_type | type_rest]} = state),
    do: {:ok, expr, %{state | stack: rest, stack_types: type_rest}}

  def pop(_state), do: {:error, :stack_underflow}

  @doc "Pops several operand-stack expressions preserving evaluation order."
  def pop_n(state, 0), do: {:ok, [], state}

  def pop_n(state, count) when count > 0 do
    with {:ok, expr, state} <- pop(state),
         {:ok, rest, state} <- pop_n(state, count - 1) do
      {:ok, [expr | rest], state}
    end
  end

  @doc "Pops several operand-stack expressions with their inferred types."
  def pop_n_typed(state, 0), do: {:ok, [], [], state}

  def pop_n_typed(state, count) when count > 0 do
    with {:ok, expr, type, state} <- pop_typed(state),
         {:ok, rest, rest_types, state} <- pop_n_typed(state, count - 1) do
      {:ok, [expr | rest], [type | rest_types], state}
    end
  end

  @doc "Binds a stack entry to a temporary variable when it must be evaluated once."
  def bind_stack_entry(state, idx) do
    case Enum.fetch(state.stack, idx) do
      {:ok, expr} ->
        {bound, state} = bind(state, Builder.temp_name(state.temp), expr)
        {:ok, %{state | stack: List.replace_at(state.stack, idx, bound)}, bound}

      :error ->
        :error
    end
  end
end
