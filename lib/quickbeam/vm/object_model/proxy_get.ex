defmodule QuickBEAM.VM.ObjectModel.ProxyGet do
  @moduledoc "Proxy [[Get]] dispatch and invariant validation."

  alias QuickBEAM.VM.{Heap, JSThrow}
  alias QuickBEAM.VM.ObjectModel.{ProxyDispatch, ProxyTrap, Semantics}

  def dispatch(proxy_map, target, handler, key, receiver, fallback, target_slot)
      when is_function(fallback, 3) and is_function(target_slot, 2) do
    ProxyDispatch.target_handler!(proxy_map)
    get_trap(target, handler, key, receiver, fallback, target_slot)
  end

  def validate_invariant(target, key, trap_result, target_slot)
      when is_function(target_slot, 2) do
    case target do
      {:obj, target_ref} -> validate_object_invariant(target_ref, key, trap_result, target_slot)
      _ -> trap_result
    end
  end

  defp get_trap(target, handler, key, receiver, fallback, target_slot) do
    trap = ProxyDispatch.trap(handler, "get")

    if is_nil(ProxyDispatch.callable_trap!(trap, "get")) do
      fallback.(target, key, receiver)
    else
      trap_result = ProxyTrap.call(trap, [target, key, receiver], handler)
      validate_invariant(target, key, trap_result, target_slot)
    end
  end

  defp validate_object_invariant(target_ref, key, trap_result, target_slot) do
    desc = Heap.get_prop_desc(target_ref, key)
    target_value = target_slot.({:obj, target_ref}, key)

    cond do
      match?(%{configurable: false, writable: false}, desc) and
        not match?({:accessor, _, _}, target_value) and
          not Semantics.same_value?(trap_result, target_value) ->
        JSThrow.type_error!("proxy get trap violates invariant")

      match?(%{configurable: false}, desc) and match?({:accessor, nil, _}, target_value) and
          trap_result != :undefined ->
        JSThrow.type_error!("proxy get trap violates invariant")

      true ->
        trap_result
    end
  end
end
