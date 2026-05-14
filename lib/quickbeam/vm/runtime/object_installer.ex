defmodule QuickBEAM.VM.Runtime.ObjectInstaller do
  @moduledoc "Installs Object constructor and Object.prototype constructor metadata."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry
  alias QuickBEAM.VM.Runtime.Globals.Constructors
  alias QuickBEAM.VM.Runtime.Object

  @doc "Returns the global Object constructor binding."
  def binding do
    obj_proto = ensure_object_prototype()

    obj_ctor =
      ConstructorRegistry.register("Object", &Constructors.object/2,
        module: Object,
        prototype: obj_proto
      )

    install_constructor_on_prototype(obj_proto, obj_ctor)
    {"Object", obj_ctor}
  end

  defp ensure_object_prototype do
    case Heap.get_object_prototype() do
      nil -> Object.build_prototype()
      existing -> existing
    end
  end

  defp install_constructor_on_prototype({:obj, proto_ref}, obj_ctor) do
    case Heap.get_obj(proto_ref, %{}) do
      map when is_map(map) -> Heap.put_obj(proto_ref, Map.put(map, "constructor", obj_ctor))
      _ -> :ok
    end
  end
end
