defmodule QuickBEAM.VM.Runtime.Boolean do
  @moduledoc "JavaScript `Boolean` constructor and prototype builtins."

  use QuickBEAM.VM.Builtin
  alias QuickBEAM.VM.{Heap, JSThrow}
  alias QuickBEAM.VM.ObjectModel.{InternalMethods, WrappedPrimitive}
  alias QuickBEAM.VM.Runtime

  @ecma "20.3"
  defintrinsic "Boolean" do
    constructor length: 1, phase: :fundamental do
      case {args, this} do
        {args, {:obj, _} = this} ->
          val = args |> arg(0, false) |> Runtime.truthy?()
          InternalMethods.set(this, WrappedPrimitive.slot(:boolean), val)
          this

        {args, _} ->
          args |> arg(0, false) |> Runtime.truthy?()
      end
    end

    install do
      prototype extends: :object do
        internal_slot(WrappedPrimitive.slot(:boolean), false)
        properties()
        constructor_link()
      end
    end
  end

  @ecma "20.3.3.2"
  proto "toString" do
    Atom.to_string(unwrap_boolean(this))
  end

  @ecma "20.3.3.3"
  proto "valueOf" do
    unwrap_boolean(this)
  end

  defp unwrap_boolean({:obj, ref}) do
    case Heap.get_obj(ref, %{}) |> WrappedPrimitive.value(:boolean) do
      {:ok, value} -> value
      :error -> JSThrow.type_error!("Boolean method called on incompatible receiver")
    end
  end

  defp unwrap_boolean(value) when is_boolean(value), do: value

  defp unwrap_boolean(_value),
    do: JSThrow.type_error!("Boolean method called on incompatible receiver")
end
