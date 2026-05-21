defmodule QuickBEAM.VM.RuntimeState do
  @moduledoc "Scoped access to process-local VM runtime context state."

  alias QuickBEAM.VM.Heap

  @doc "Returns the current process-local VM context."
  def current, do: Heap.get_ctx()

  @doc "Installs a process-local VM context."
  def install(ctx), do: Heap.put_ctx(ctx)

  @doc "Restores a previously captured context, clearing state when nil."
  def restore(nil), do: Heap.put_ctx(nil)
  def restore(ctx), do: Heap.put_ctx(ctx)

  @doc "Runs a function with a temporary process-local VM context."
  def with_context(ctx, fun) when is_function(fun, 0) do
    previous = current()
    install(ctx)

    try do
      fun.()
    after
      restore(previous)
    end
  end
end
