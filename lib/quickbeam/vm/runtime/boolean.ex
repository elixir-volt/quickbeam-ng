defmodule QuickBEAM.VM.Runtime.Boolean do
  @moduledoc "JavaScript `Boolean` constructor and prototype builtins."

  use QuickBEAM.VM.Builtin
  alias QuickBEAM.VM.ObjectModel.WrappedPrimitive
  alias QuickBEAM.VM.Runtime
  alias QuickBEAM.VM.Runtime.InstallerHelpers

  builtin_definition("Boolean",
    constructor: constructor(),
    length: 1,
    phase: :fundamental,
    after_install: &__MODULE__.install_builtin/1
  )

  def install_builtin(ctor) do
    InstallerHelpers.with_prototype(ctor, fn proto_ref ->
      InstallerHelpers.install_object_parent(proto_ref)
      InstallerHelpers.install_methods(proto_ref, __MODULE__, ~w(toString valueOf))
      InstallerHelpers.install_constructor_link(proto_ref, ctor)
    end)
  end

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
