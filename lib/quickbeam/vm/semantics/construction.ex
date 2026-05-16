defmodule QuickBEAM.VM.Semantics.Construction do
  @moduledoc "Shared object construction semantics for interpreter and compiler paths."

  import QuickBEAM.VM.Heap.Keys, only: [proto: 0]

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.{Class, Functions}

  def new_object do
    object_proto = Heap.get_object_prototype()
    init = if object_proto, do: %{proto() => object_proto}, else: %{}
    Heap.wrap(init)
  end

  def check_ctor_return(value) do
    case Class.check_ctor_return(value) do
      {replace_with_this?, checked_val} -> {:ok, replace_with_this?, checked_val}
      :error -> {:error, "Derived constructors may only return object or undefined"}
    end
  end

  def special_object(type, current_func, arg_buf, new_target, home_object) do
    case type do
      0 ->
        arguments_object(current_func, arg_buf)

      1 ->
        arguments_object(current_func, arg_buf)

      2 ->
        current_func

      3 ->
        new_target

      4 ->
        if(home_object == :undefined,
          do: Functions.current_home_object(current_func),
          else: home_object
        )

      5 ->
        Heap.wrap(%{})

      6 ->
        Heap.wrap(%{})

      7 ->
        Heap.wrap(%{"__proto__" => nil})

      _ ->
        :undefined
    end
  end

  defp arguments_object(current_func, arg_buf) do
    Heap.wrap_arguments(Tuple.to_list(arg_buf),
      strict: strict_function?(current_func),
      callee: current_func
    )
  end

  defp strict_function?({:closure, _, %QuickBEAM.VM.Function{is_strict_mode: strict}}), do: strict
  defp strict_function?(%QuickBEAM.VM.Function{is_strict_mode: strict}), do: strict
  defp strict_function?(_), do: false
end
