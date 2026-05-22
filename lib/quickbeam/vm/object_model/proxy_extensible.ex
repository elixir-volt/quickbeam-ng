defmodule QuickBEAM.VM.ObjectModel.ProxyExtensible do
  @moduledoc "Proxy [[IsExtensible]] dispatch and invariant validation."

  import QuickBEAM.VM.Heap.Keys, only: [proxy_handler: 0, proxy_target: 0]

  alias QuickBEAM.VM.{Heap, JSThrow, Value}
  alias QuickBEAM.VM.ObjectModel.{Get, ProxyTrap}
  alias QuickBEAM.VM.Semantics.Values

  def dispatch({:obj, ref} = proxy, fallback) when is_function(fallback, 1) do
    case Heap.get_obj(ref, %{}) do
      %{proxy_target() => _target, "__proxy_revoked__" => true} ->
        JSThrow.type_error!("Cannot perform operation on a revoked proxy")

      %{proxy_target() => _target, proxy_handler() => handler}
      when not is_map(handler) and not is_tuple(handler) ->
        JSThrow.type_error!("Cannot perform operation on a proxy with null handler")

      %{proxy_target() => target, proxy_handler() => handler} ->
        extensible_trap(target, handler, fallback)

      _ ->
        fallback.(proxy)
    end
  end

  def dispatch(target, fallback) when is_function(fallback, 1), do: fallback.(target)

  def validate_invariant(trap_result, target_result) do
    if trap_result == target_result do
      trap_result
    else
      JSThrow.type_error!("proxy isExtensible trap violates invariant")
    end
  end

  defp extensible_trap(target, handler, fallback) do
    trap = Get.get(handler, "isExtensible")

    if Value.nullish?(trap) do
      fallback.(target)
    else
      trap
      |> ProxyTrap.call([target], handler)
      |> Values.truthy?()
      |> validate_invariant(fallback.(target))
    end
  end
end
