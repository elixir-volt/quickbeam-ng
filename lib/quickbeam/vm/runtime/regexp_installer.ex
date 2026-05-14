defmodule QuickBEAM.VM.Runtime.RegExpInstaller do
  @moduledoc "Installs the RegExp constructor, prototype methods, accessors, and symbol hooks."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.PropertyDescriptor
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.Globals.Constructors
  alias QuickBEAM.VM.Runtime.RegExp

  @accessors ~w(source global ignoreCase multiline)
  @methods ~w(exec test toString)
  @symbol_methods [
    {:symbol, "Symbol.match"},
    {:symbol, "Symbol.matchAll"},
    {:symbol, "Symbol.replace"},
    {:symbol, "Symbol.search"}
  ]

  @doc "Returns the global RegExp constructor binding."
  def constructor do
    ctor =
      ConstructorRegistry.register("RegExp", &Constructors.regexp/2,
        module: RegExp,
        auto_proto: true
      )

    install_prototype_methods(ctor)
    install_prototype_accessors(ctor)
    install_symbol_properties(ctor)
    ctor
  end

  defp install_prototype_methods(ctor) do
    with_prototype(ctor, fn proto_ref ->
      for name <- @methods do
        Heap.put_obj_key(proto_ref, name, RegExp.proto_property(name))
        Heap.put_prop_desc(proto_ref, name, PropertyDescriptor.method())
      end
    end)
  end

  defp install_prototype_accessors(ctor) do
    with_prototype(ctor, fn proto_ref ->
      for name <- @accessors do
        Heap.put_obj_key(proto_ref, name, RegExp.proto_accessor(name))
        Heap.put_prop_desc(proto_ref, name, PropertyDescriptor.accessor())
      end
    end)
  end

  defp install_symbol_properties(ctor) do
    sym_species = {:symbol, "Symbol.species"}

    Heap.put_ctor_static(
      ctor,
      sym_species,
      {:accessor, {:builtin, "get [Symbol.species]", fn _args, this -> this end}, nil}
    )

    Heap.put_ctor_prop_desc(ctor, sym_species, PropertyDescriptor.accessor())

    with_prototype(ctor, fn proto_ref ->
      for symbol <- @symbol_methods do
        Heap.put_obj_key(proto_ref, symbol, RegExp.proto_property(symbol))
        Heap.put_prop_desc(proto_ref, symbol, PropertyDescriptor.method())
      end
    end)
  end

  defp with_prototype(ctor, fun) do
    case Heap.get_ctor_statics(ctor)["prototype"] do
      {:obj, proto_ref} -> fun.(proto_ref)
      _ -> :ok
    end
  end
end
