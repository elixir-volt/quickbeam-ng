defmodule QuickBEAM.VM.Runtime.Boolean do
  @moduledoc "JavaScript `Boolean` constructor and prototype builtins."

  use QuickBEAM.VM.Builtin
  alias QuickBEAM.VM.ObjectModel.WrappedPrimitive
  alias QuickBEAM.VM.Runtime

  proto "toString" do
    Atom.to_string(unwrap_boolean(this))
  end

  proto "valueOf" do
    unwrap_boolean(this)
  end

  defp unwrap_boolean({:obj, ref}) do
    case QuickBEAM.VM.Heap.get_obj(ref, %{}) |> WrappedPrimitive.value(:boolean) do
      {:ok, value} -> value
      :error -> true
    end
  end

  defp unwrap_boolean(value), do: Runtime.truthy?(value)

  @doc "Builds the JavaScript constructor object for this runtime builtin."
  def constructor do
    fn
      args, {:obj, _} = this ->
        val = args |> arg(0, false) |> Runtime.truthy?()
        QuickBEAM.VM.ObjectModel.Put.put(this, WrappedPrimitive.slot(:boolean), val)
        this

      args, _ ->
        args |> arg(0, false) |> Runtime.truthy?()
    end
  end
end
