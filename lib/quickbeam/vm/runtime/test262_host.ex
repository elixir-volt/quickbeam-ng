defmodule QuickBEAM.VM.Runtime.Test262Host do
  @moduledoc "Minimal Test262 host hooks used by compatibility tests."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.Runtime.Array
  alias QuickBEAM.VM.Runtime.Map, as: JSMap
  alias QuickBEAM.VM.Runtime.Set, as: JSSet
  alias QuickBEAM.VM.Runtime.Globals.Constructors
  alias QuickBEAM.VM.Runtime.Constructors, as: ConstructorRegistry

  def object do
    Heap.wrap(%{
      "createRealm" => {:builtin, "createRealm", fn _, _ -> create_realm() end}
    })
  end

  def create_realm do
    object_proto = Heap.wrap(%{})
    object_ctor = realm_constructor("Object", &Constructors.object/2, object_proto)
    Heap.put_obj_key(elem(object_proto, 1), "constructor", object_ctor)

    array_proto = Array.prototype()
    array_ctor = realm_constructor("Array", &Constructors.array/2, array_proto)
    Heap.put_obj_key(elem(array_proto, 1), "constructor", array_ctor)

    weak_map_proto = Heap.wrap(%{"__proto__" => object_proto})
    weak_map_ctor = realm_constructor("WeakMap", JSMap.weak_constructor(), weak_map_proto)
    Heap.put_obj_key(elem(weak_map_proto, 1), "constructor", weak_map_ctor)

    weak_set_proto = Heap.wrap(%{"__proto__" => object_proto})
    weak_set_ctor = realm_constructor("WeakSet", JSSet.weak_constructor(), weak_set_proto)
    Heap.put_obj_key(elem(weak_set_proto, 1), "constructor", weak_set_ctor)

    function_proto = QuickBEAM.VM.Runtime.Function.prototype()

    function_ctor =
      realm_function_constructor(
        object_proto,
        function_proto,
        array_proto,
        weak_map_proto,
        weak_set_proto
      )

    global =
      Heap.wrap(%{
        "Object" => object_ctor,
        "Array" => array_ctor,
        "Function" => function_ctor,
        "WeakMap" => weak_map_ctor,
        "WeakSet" => weak_set_ctor
      })

    Heap.wrap(%{"global" => global})
  end

  def realm_intrinsic(constructor, intrinsic) do
    case Process.get({:qb_realm_intrinsics, constructor}) do
      %{array_proto: array_proto} when intrinsic == :array -> array_proto
      %{weak_map_proto: weak_map_proto} when intrinsic == :weak_map -> weak_map_proto
      %{weak_set_proto: weak_set_proto} when intrinsic == :weak_set -> weak_set_proto
      %{object_proto: object_proto} when intrinsic == :object -> object_proto
      _ -> nil
    end
  end

  defp realm_constructor(name, callback, proto) do
    cb = fn args, this -> callback.(args, this) end
    ctor = {:builtin, name, cb}
    ConstructorRegistry.put_prototype(ctor, proto)
    ctor
  end

  defp realm_function_constructor(
         object_proto,
         function_proto,
         array_proto,
         weak_map_proto,
         weak_set_proto
       ) do
    cb = fn _args, _this ->
      fun = {:builtin, "anonymous", fn _, this -> this end}
      Heap.put_class_proto(fun, object_proto)
      Heap.put_ctor_static(fun, "prototype", :undefined)

      Process.put({:qb_realm_intrinsics, fun}, %{
        object_proto: object_proto,
        array_proto: array_proto,
        weak_map_proto: weak_map_proto,
        weak_set_proto: weak_set_proto
      })

      fun
    end

    ctor = {:builtin, "Function", cb}
    ConstructorRegistry.put_prototype(ctor, function_proto)

    Process.put({:qb_realm_intrinsics, ctor}, %{
      object_proto: object_proto,
      array_proto: array_proto,
      weak_map_proto: weak_map_proto,
      weak_set_proto: weak_set_proto
    })

    ctor
  end
end
