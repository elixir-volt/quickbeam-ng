defmodule QuickBEAM.VM.Runtime.DateInstaller do
  @moduledoc "Installs the Date constructor, prototype methods, and Symbol.toPrimitive hook."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.PropertyDescriptor
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.Date, as: JSDate

  @doc "Returns the global Date constructor binding."
  def constructor do
    ctor =
      ConstructorRegistry.register("Date", &JSDate.constructor/2,
        module: JSDate,
        auto_proto: true
      )

    install_prototype_methods(ctor)
    install_prototype_descriptor(ctor)
    install_symbol_to_primitive(ctor)
    ctor
  end

  defp install_prototype_methods(ctor) do
    with_prototype(ctor, fn proto_ref ->
      for name <- JSDate.proto_property_names() do
        Heap.put_obj_key(proto_ref, name, JSDate.proto_property(name))
        Heap.put_prop_desc(proto_ref, name, PropertyDescriptor.method())
      end
    end)
  end

  defp install_prototype_descriptor(ctor) do
    Heap.put_ctor_prop_desc(ctor, "prototype", PropertyDescriptor.prototype())
  end

  defp install_symbol_to_primitive(ctor) do
    with_prototype(ctor, fn proto_ref ->
      Heap.put_prop_desc(proto_ref, "constructor", PropertyDescriptor.method())

      sym_key = {:symbol, "Symbol.toPrimitive"}

      to_prim =
        {:builtin, "[Symbol.toPrimitive]",
         fn args, this ->
           JSDate.symbol_to_primitive(this, args)
         end}

      Heap.put_ctor_static(to_prim, "length", 1)
      Heap.put_ctor_prop_desc(to_prim, "length", PropertyDescriptor.hidden_readonly())
      Heap.put_obj_key(proto_ref, sym_key, to_prim)
      Heap.put_prop_desc(proto_ref, sym_key, PropertyDescriptor.hidden_readonly())
    end)
  end

  defp with_prototype(ctor, fun) do
    case Heap.get_ctor_statics(ctor)["prototype"] do
      {:obj, proto_ref} -> fun.(proto_ref)
      _ -> :ok
    end
  end
end
