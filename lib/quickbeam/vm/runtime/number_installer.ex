defmodule QuickBEAM.VM.Runtime.NumberInstaller do
  @moduledoc "Installs the Number constructor, prototype methods, and numeric constant descriptors."

  alias QuickBEAM.VM.Builtin
  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.PropertyDescriptor
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.Globals.Constructors
  alias QuickBEAM.VM.Runtime.InstallerHelpers
  alias QuickBEAM.VM.Runtime.Number

  @methods ~w(toString toFixed valueOf toExponential toPrecision toLocaleString)
  @constants ~w(NaN POSITIVE_INFINITY NEGATIVE_INFINITY MAX_SAFE_INTEGER MIN_SAFE_INTEGER EPSILON MAX_VALUE MIN_VALUE)

  @doc "Returns the global Number constructor binding."
  def constructor do
    ctor =
      ConstructorRegistry.register("Number", &Constructors.number/2,
        module: Number,
        auto_proto: true
      )

    install_prototype_methods(ctor)
    install_method_lengths(ctor)
    install_static_descriptors(ctor)
    install_prototype_metadata(ctor)

    ctor
  end

  defp install_prototype_methods(ctor) do
    InstallerHelpers.with_prototype(ctor, fn proto_ref ->
      InstallerHelpers.install_methods(proto_ref, Number, @methods)
    end)
  end

  defp install_method_lengths(ctor) do
    InstallerHelpers.with_prototype(ctor, fn proto_ref ->
      for name <- @methods do
        case Heap.get_obj(proto_ref, %{}) do
          %{^name => method} ->
            length = Builtin.length(Builtin.proto_meta(Number, name))
            Heap.put_ctor_static(method, "length", length)
            Heap.put_ctor_prop_desc(method, "length", PropertyDescriptor.hidden_readonly())

          _ ->
            :ok
        end
      end
    end)
  end

  defp install_static_descriptors(ctor) do
    Heap.put_ctor_prop_desc(ctor, "prototype", PropertyDescriptor.prototype())

    for name <- @constants do
      Heap.put_ctor_prop_desc(ctor, name, PropertyDescriptor.prototype())
    end
  end

  defp install_prototype_metadata(ctor) do
    InstallerHelpers.with_prototype(ctor, fn proto_ref ->
      InstallerHelpers.install_object_parent(proto_ref)
      Heap.put_obj_key(proto_ref, "__wrapped_number__", 0)
      InstallerHelpers.install_constructor_link(proto_ref, ctor)
    end)
  end
end
