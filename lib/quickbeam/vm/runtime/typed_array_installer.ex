defmodule QuickBEAM.VM.Runtime.TypedArrayInstaller do
  @moduledoc "Installs typed-array constructors and their shared abstract superclass."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.PropertyDescriptor
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.TypedArray

  @doc "Returns global bindings for all typed-array constructors."
  def bindings do
    ta_base = abstract_typed_array_constructor()
    install_base_prototype(ta_base)

    base_proto = Heap.get_class_proto(ta_base)

    for {name, type} <- TypedArray.types(), into: %{} do
      ctor =
        ConstructorRegistry.register(
          name,
          TypedArray.constructor(type),
          TypedArray.prototype_properties(),
          base_proto
        )

      mark_prototype_methods(ctor)
      Heap.put_ctor_static(ctor, "__proto__", ta_base)
      Heap.put_ctor_static(ctor, "BYTES_PER_ELEMENT", TypedArray.elem_size(type))
      {name, ctor}
    end
  end

  defp abstract_typed_array_constructor do
    {:builtin, "TypedArray",
     fn _args, _this ->
       throw(
         {:js_throw, Heap.make_error("Abstract class TypedArray cannot be called", "TypeError")}
       )
     end}
  end

  defp install_base_prototype(ta_base) do
    ta_base_ref = make_ref()

    Heap.put_obj(
      ta_base_ref,
      Map.put(TypedArray.prototype_properties(), "__proto__", nil)
    )

    Heap.put_prop_desc(ta_base_ref, "at", PropertyDescriptor.method())
    Heap.put_ctor_static(ta_base, "prototype", {:obj, ta_base_ref})
  end

  defp mark_prototype_methods(ctor) do
    case Heap.get_class_proto(ctor) do
      {:obj, proto_ref} -> Heap.put_prop_desc(proto_ref, "at", PropertyDescriptor.method())
      _ -> :ok
    end
  end
end
