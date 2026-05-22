defmodule QuickBEAM.VM.ObjectModel.ProxyDelete do
  @moduledoc "Proxy [[Delete]] dispatch and invariant validation."

  import QuickBEAM.VM.Heap.Keys, only: [proxy_handler: 0, proxy_target: 0]

  alias QuickBEAM.VM.{Heap, JSThrow, Value}
  alias QuickBEAM.VM.ObjectModel.{Get, ProxyTrap}
  alias QuickBEAM.VM.Semantics.Values

  def dispatch({:obj, ref} = proxy, key, fallback) when is_function(fallback, 2) do
    case Heap.get_obj(ref, %{}) do
      %{proxy_target() => _target, "__proxy_revoked__" => true} ->
        JSThrow.type_error!("Cannot perform operation on a revoked proxy")

      %{proxy_target() => _target, proxy_handler() => handler}
      when not is_map(handler) and not is_tuple(handler) ->
        JSThrow.type_error!("Cannot perform operation on a proxy with null handler")

      %{proxy_target() => target, proxy_handler() => handler} ->
        delete_trap(target, handler, key, fallback)

      _ ->
        fallback.(proxy, key)
    end
  end

  def dispatch(target, key, fallback) when is_function(fallback, 2),
    do: fallback.(target, key)

  def validate_invariant({:obj, target_ref}, key, true) do
    case Heap.get_prop_desc(target_ref, key) do
      %{configurable: false} ->
        JSThrow.type_error!("proxy deleteProperty trap violates invariant")

      _ ->
        true
    end
  end

  def validate_invariant(_target, _key, result), do: result

  defp delete_trap(target, handler, key, fallback) do
    trap = Get.get(handler, "deleteProperty")

    if Value.nullish?(trap) do
      fallback.(target, key)
    else
      trap_result = trap |> ProxyTrap.call([target, key], handler) |> Values.truthy?()
      validate_invariant(target, key, trap_result)
    end
  end
end
