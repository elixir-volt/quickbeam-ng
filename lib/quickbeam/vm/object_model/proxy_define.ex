defmodule QuickBEAM.VM.ObjectModel.ProxyDefine do
  @moduledoc "Proxy [[DefineOwnProperty]] dispatch and invariant validation."

  import QuickBEAM.VM.Heap.Keys, only: [proxy_target: 0]

  alias QuickBEAM.VM.{Heap, JSThrow}
  alias QuickBEAM.VM.ObjectModel.{ProxyDispatch, ProxyTrap}
  alias QuickBEAM.VM.Semantics.Values

  def dispatch({:obj, ref} = proxy, key, prop_name, desc_obj, fallback, invariant?)
      when is_function(fallback, 3) and is_function(invariant?, 3) do
    case Heap.get_obj(ref, %{}) do
      %{proxy_target() => _target} = proxy_map ->
        {target, handler} = ProxyDispatch.target_handler!(proxy_map)
        define_trap(proxy, target, handler, key, prop_name, desc_obj, fallback, invariant?)

      _ ->
        fallback.(proxy, key, desc_obj)
    end
  end

  def dispatch(target, key, _prop_name, desc_obj, fallback, _invariant?)
      when is_function(fallback, 3),
      do: fallback.(target, key, desc_obj)

  defp define_trap(proxy, target, handler, key, prop_name, desc_obj, fallback, invariant?) do
    trap = ProxyDispatch.trap(handler, "defineProperty")

    cond do
      is_nil(ProxyDispatch.callable_trap!(trap, "defineProperty")) ->
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
