defmodule QuickBEAM.VM.ObjectModel.ProxyDefine do
  @moduledoc "Proxy [[DefineOwnProperty]] dispatch and invariant validation."

  import QuickBEAM.VM.Heap.Keys, only: [proxy_handler: 0, proxy_target: 0]

  alias QuickBEAM.VM.{Heap, JSThrow, Value}
  alias QuickBEAM.VM.ObjectModel.{Get, ProxyTrap}
  alias QuickBEAM.VM.Semantics.Values

  def dispatch({:obj, ref} = proxy, key, prop_name, desc_obj, fallback, invariant?)
      when is_function(fallback, 3) and is_function(invariant?, 3) do
    case Heap.get_obj(ref, %{}) do
      %{proxy_target() => _target, "__proxy_revoked__" => true} ->
        JSThrow.type_error!("Cannot perform operation on a revoked proxy")

      %{proxy_target() => _target, proxy_handler() => handler}
      when not is_map(handler) and not is_tuple(handler) ->
        JSThrow.type_error!("Cannot perform operation on a proxy with null handler")

      %{proxy_target() => target, proxy_handler() => handler} ->
        define_trap(proxy, target, handler, key, prop_name, desc_obj, fallback, invariant?)

      _ ->
        fallback.(proxy, key, desc_obj)
    end
  end

  def dispatch(target, key, _prop_name, desc_obj, fallback, _invariant?)
      when is_function(fallback, 3),
      do: fallback.(target, key, desc_obj)

  defp define_trap(proxy, target, handler, key, prop_name, desc_obj, fallback, invariant?) do
    trap = Get.get(handler, "defineProperty")

    cond do
      Value.nullish?(trap) ->
        fallback.(target, key, desc_obj)
        proxy

      not Values.truthy?(ProxyTrap.call(trap, [target, prop_name, desc_obj], handler)) ->
        JSThrow.type_error!("proxy defineProperty trap returned false")

      invariant?.(target, prop_name, descriptor_map(desc_obj)) ->
        JSThrow.type_error!("proxy defineProperty trap violates invariant")

      true ->
        proxy
    end
  end

  defp descriptor_map({:obj, ref}) do
    case Heap.get_obj(ref, %{}) do
      map when is_map(map) -> map
      _ -> %{}
    end
  end

  defp descriptor_map(_), do: %{}
end
