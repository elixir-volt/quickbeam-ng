defmodule QuickBEAM.VM.Runtime.ArrayBufferInstaller do
  @moduledoc "Installs the ArrayBuffer constructor, prototype methods, and Symbol.species accessor."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.Runtime.ArrayBuffer
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.InstallerHelpers

  @doc "Returns the global ArrayBuffer constructor binding."
  def constructor do
    ctor =
      ConstructorRegistry.register("ArrayBuffer", &ArrayBuffer.constructor/2, auto_proto: true)

    install_prototype_methods(ctor)
    install_species(ctor)
    ctor
  end

  defp install_prototype_methods(ctor) do
    InstallerHelpers.with_prototype(ctor, fn proto_ref ->
      InstallerHelpers.install_methods(proto_ref, ArrayBuffer, ArrayBuffer.proto_property_names())
    end)
  end

  defp install_species(ctor) do
    Heap.put_ctor_static(
      ctor,
      {:symbol, "Symbol.species"},
      {:accessor, {:builtin, "get [Symbol.species]", fn _, _ -> ctor end}, nil}
    )
  end
end
