defmodule QuickBEAM.VM.Runtime.InstallerHelpers do
  @moduledoc "Reusable helpers for installing constructor/prototype metadata."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.ObjectModel.{InternalMethods, PropertyDescriptor}

  @doc "Runs `fun` with a constructor's prototype object reference when present."
  def with_prototype(ctor, fun) when is_function(fun, 1) do
    case Heap.get_ctor_statics(ctor)["prototype"] do
      {:obj, proto_ref} -> fun.(proto_ref)
      _ -> :ok
    end
  end

  @doc "Sets a prototype object's parent to Object.prototype."
  def install_object_parent(proto_ref, parent \\ Heap.get_object_prototype()) do
    Heap.put_obj_key(proto_ref, "__proto__", parent)
  end

  @doc "Installs methods using a custom method lookup function."
  def install_methods_with(proto_ref, names, lookup_fun) when is_function(lookup_fun, 1) do
    for name <- names do
      Heap.put_obj_key(proto_ref, name, lookup_fun.(name))
      Heap.put_prop_desc(proto_ref, name, PropertyDescriptor.method())
    end
  end

  @doc "Installs a non-enumerable constructor link on a prototype object."
  def install_constructor_link(proto_ref, ctor) do
    InternalMethods.set({:obj, proto_ref}, "constructor", ctor)
    Heap.put_prop_desc(proto_ref, "constructor", PropertyDescriptor.method())
  end

  @doc "Installs Symbol.toStringTag on a prototype object."
  def install_to_string_tag(proto_ref, label) do
    sym_to_string_tag = {:symbol, "Symbol.toStringTag"}
    Heap.put_obj_key(proto_ref, sym_to_string_tag, label)
    Heap.put_prop_desc(proto_ref, sym_to_string_tag, PropertyDescriptor.hidden_readonly())
  end

  @doc "Installs a hidden readonly constructor/function static."
  def install_hidden_static(ctor, name, value) do
    Heap.put_ctor_static(ctor, name, value)
    Heap.put_ctor_prop_desc(ctor, name, PropertyDescriptor.hidden_readonly())
  end
end
