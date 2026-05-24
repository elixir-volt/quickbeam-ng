defmodule QuickBEAM.VM.ObjectModel.ProxyPrototype do
  @moduledoc "Proxy [[GetPrototypeOf]] and [[SetPrototypeOf]] dispatch."

  alias QuickBEAM.VM.{Heap, JSThrow}
  alias QuickBEAM.VM.ObjectModel.{ProxyDispatch, ProxyTrap, Prototype}
  alias QuickBEAM.VM.Semantics.Values

  def get(proxy_map, fallback) when is_function(fallback, 1) do
    ProxyDispatch.with_trap(proxy_map, "getPrototypeOf", fallback, fn target, handler, trap ->
      trap
      |> ProxyTrap.call([target], handler)
      |> validate_get_result(target)
    end)
  end

  def set(proxy_map, new_proto, fallback) when is_function(fallback, 2) do
    proxy_fallback = fn target -> fallback.(target, new_proto) end

    ProxyDispatch.with_trap(proxy_map, "setPrototypeOf", proxy_fallback, fn target,
                                                                            handler,
                                                                            trap ->
      trap
      |> ProxyTrap.call([target, new_proto], handler)
      |> Values.truthy?()
      |> validate_set_result(target, new_proto)
    end)
  end

  defp validate_get_result(result, target) do
    cond do
      not prototype_value?(result) ->
        prototype_invariant_error()

      not target_extensible?(target) and result != Prototype.get(target) ->
        prototype_invariant_error()

      true ->
        result
    end
  end

  defp validate_set_result(false, _target, _new_proto), do: false

  defp validate_set_result(true, target, new_proto) do
    if not target_extensible?(target) and new_proto != Prototype.get(target) do
      prototype_invariant_error()
    end

    true
  end

  defp prototype_value?(nil), do: true
  defp prototype_value?({:obj, _}), do: true
  defp prototype_value?(_), do: false

  defp target_extensible?({:obj, ref}), do: Heap.extensible?(ref)
  defp target_extensible?(_), do: true

  defp prototype_invariant_error,
    do: JSThrow.type_error!("proxy prototype trap violates invariant")
end
