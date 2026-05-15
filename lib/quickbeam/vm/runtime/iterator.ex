defmodule QuickBEAM.VM.Runtime.Iterator do
  @moduledoc "JavaScript Iterator constructor and basic wrapping support."

  use QuickBEAM.VM.Builtin

  alias QuickBEAM.VM.{Builtin, Heap, Invocation, JSThrow}
  alias QuickBEAM.VM.ObjectModel.Get
  alias QuickBEAM.VM.Runtime

  def constructor do
    fn _args, this ->
      iterator_proto = Runtime.global_class_proto("Iterator")

      case this do
        {:obj, ref} = obj ->
          if Map.get(Heap.get_obj(ref, %{}), "__proto__") == iterator_proto do
            JSThrow.type_error!("Iterator is not constructible")
          else
            obj
          end

        _ ->
          JSThrow.type_error!("Iterator is not callable")
      end
    end
  end

  def static_property("from") do
    from = {:builtin, "from", &from/2}
    Heap.put_ctor_static(from, "length", 1)
    Heap.put_ctor_static(from, "name", "from")
    from
  end

  def static_property(_), do: :undefined

  def proto_property({:symbol, "Symbol.iterator"}) do
    {:builtin, "[Symbol.iterator]", fn _args, this -> this end}
  end

  def proto_property(_), do: :undefined

  def from([value | _], _this), do: from_value(value)
  def from(_, _this), do: JSThrow.type_error!("Iterator.from requires an object")

  defp from_value(value) do
    unless object_like?(value), do: JSThrow.type_error!("Iterator.from requires an object")

    iterator_method = Get.get(value, {:symbol, "Symbol.iterator"})

    iterator =
      if Builtin.callable?(iterator_method) do
        result = Invocation.invoke_with_receiver(iterator_method, [], value)

        unless object_like?(result),
          do: JSThrow.type_error!("iterator method returned non-object")

        result
      else
        value
      end

    if iterator_method != :undefined and iterator_method != nil and iterator == value do
      iterator
    else
      wrap_iterator(iterator)
    end
  end

  defp wrap_iterator(iterator) do
    proto = wrap_for_valid_iterator_prototype()

    Heap.wrap(%{
      "__proto__" => proto,
      "__wrapped_iterator__" => iterator,
      "next" => {:builtin, "next", fn _args, this -> wrapper_next(this) end},
      "return" => {:builtin, "return", fn _args, this -> wrapper_return(this) end},
      {:symbol, "Symbol.iterator"} => {:builtin, "[Symbol.iterator]", fn _args, this -> this end}
    })
  end

  def wrap_for_valid_iterator_prototype do
    proto = Runtime.global_class_proto("Iterator")

    case Process.get(:qb_wrap_for_valid_iterator_prototype) do
      {:obj, _} = cached ->
        cached

      _ ->
        wrapper =
          Heap.wrap(%{
            "__proto__" => proto,
            "next" => {:builtin, "next", fn _args, this -> wrapper_next(this) end},
            "return" => {:builtin, "return", fn _args, this -> wrapper_return(this) end},
            {:symbol, "Symbol.iterator"} =>
              {:builtin, "[Symbol.iterator]", fn _args, this -> this end}
          })

        Process.put(:qb_wrap_for_valid_iterator_prototype, wrapper)
        wrapper
    end
  end

  defp wrapper_next(this), do: call_wrapped(this, "next", [])

  defp wrapper_return(this) do
    iterator = wrapped_iterator!(this)
    return_method = Get.get(iterator, "return")

    if Builtin.callable?(return_method) do
      Invocation.invoke_with_receiver(return_method, [], iterator)
    else
      Heap.wrap(%{"value" => :undefined, "done" => true})
    end
  end

  defp call_wrapped(this, name, args) do
    iterator = wrapped_iterator!(this)
    method = Get.get(iterator, name)
    unless Builtin.callable?(method), do: JSThrow.type_error!("Iterator method is not callable")
    result = Invocation.invoke_with_receiver(method, args, iterator)
    unless object_like?(result), do: JSThrow.type_error!("Iterator result is not an object")
    result
  end

  defp wrapped_iterator!({:obj, ref}) do
    case Heap.get_obj(ref, %{}) do
      %{"__wrapped_iterator__" => iterator} -> iterator
      _ -> JSThrow.type_error!("Iterator wrapper expected")
    end
  end

  defp wrapped_iterator!(_), do: JSThrow.type_error!("Iterator wrapper expected")

  defp object_like?({:obj, _}), do: true
  defp object_like?({:closure, _, %QuickBEAM.VM.Function{}}), do: true
  defp object_like?(%QuickBEAM.VM.Function{}), do: true
  defp object_like?({:builtin, _, _}), do: true
  defp object_like?({:bound, _, _, _, _}), do: true
  defp object_like?({:regexp, _, _}), do: true
  defp object_like?({:regexp, _, _, _}), do: true
  defp object_like?(_), do: false
end
