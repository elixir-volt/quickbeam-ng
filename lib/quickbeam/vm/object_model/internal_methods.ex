defmodule QuickBEAM.VM.ObjectModel.InternalMethods do
  @moduledoc "Dispatch facade for ECMAScript object internal methods."

  import QuickBEAM.VM.Heap.Keys, only: [proxy_handler: 0, proxy_target: 0, typed_array: 0]

  alias QuickBEAM.VM.{Heap, JSThrow, Value}
  alias QuickBEAM.VM.ObjectModel.{Define, Delete, Get, HasProperty, OwnProperty, ProxyTrap, Put}
  alias QuickBEAM.VM.Semantics.Values

  def kind({:obj, ref}) do
    case Heap.get_obj_raw(ref) do
      %{proxy_target() => _target} -> :proxy
      %{typed_array() => true} -> :typed_array
      list when is_list(list) -> :array
      _ -> :ordinary
    end
  end

  def kind(%QuickBEAM.VM.Function{}), do: :function
  def kind({:closure, _, %QuickBEAM.VM.Function{}}), do: :function
  def kind({:builtin, _, _}), do: :function
  def kind({:bound, _, _, _, _}), do: :function
  def kind(_), do: :primitive

  def get(obj, key, receiver \\ nil), do: Get.get(obj, key, receiver || obj)
  def set(obj, key, value, _receiver \\ nil), do: Put.put(obj, key, value)
  def has_property(obj, key), do: HasProperty.has_property?(obj, key)
  def own_property(obj, key), do: OwnProperty.descriptor(obj, key)

  def define_own_property(obj, key, descriptor),
    do: Define.property(obj, key, descriptor, descriptor)

  def delete(obj, key), do: Delete.delete_property(obj, key)
  def own_keys(obj), do: OwnProperty.own_keys(obj)

  def extensible?({:obj, ref}) do
    case Heap.get_obj(ref, %{}) do
      %{proxy_target() => _target, "__proxy_revoked__" => true} ->
        JSThrow.type_error!("Cannot perform operation on a revoked proxy")

      %{proxy_target() => _target, proxy_handler() => handler}
      when not is_map(handler) and not is_tuple(handler) ->
        JSThrow.type_error!("Cannot perform operation on a proxy with null handler")

      %{proxy_target() => target, proxy_handler() => handler} ->
        trap = Get.get(handler, "isExtensible")

        if Value.nullish?(trap) do
          extensible?(target)
        else
          trap_result = Values.truthy?(ProxyTrap.call(trap, [target], handler))
          target_result = extensible?(target)

          if trap_result == target_result do
            trap_result
          else
            JSThrow.type_error!("proxy isExtensible trap violates invariant")
          end
        end

      _ ->
        Heap.extensible?(ref)
    end
  end

  def extensible?(_), do: true
end
