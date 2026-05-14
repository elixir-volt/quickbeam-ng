defmodule QuickBEAM.VM.Runtime.ArrayInstaller do
  @moduledoc "Installs the Array constructor, prototype, and well-known metadata."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.PropertyDescriptor
  alias QuickBEAM.VM.Runtime.Array
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.Globals.Constructors
  alias QuickBEAM.VM.Runtime.InstallerHelpers

  @doc "Returns the global Array constructor binding."
  def constructor do
    ctor = ConstructorRegistry.register("Array", &Constructors.array/2, module: Array)
    proto = Array.prototype()

    ConstructorRegistry.put_prototype(ctor, proto)
    Heap.put_array_proto(proto)
    install_constructor_link(proto, ctor)
    InstallerHelpers.install_species(ctor)
    install_static_descriptors(ctor)

    ctor
  end

  defp install_constructor_link({:obj, proto_ref}, ctor) do
    Heap.put_obj_key(proto_ref, "constructor", ctor)
    Heap.put_prop_desc(proto_ref, "constructor", PropertyDescriptor.method())
  end

  defp install_static_descriptors(ctor) do
    Heap.put_ctor_static(ctor, "length", 1)
    Heap.put_ctor_prop_desc(ctor, "length", PropertyDescriptor.hidden_readonly())
    Heap.put_ctor_prop_desc(ctor, "prototype", PropertyDescriptor.prototype())
  end
end
