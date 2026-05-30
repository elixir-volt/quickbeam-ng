defmodule QuickBEAM.VM.ObjectModel.ProxyDelete do
  @moduledoc "Proxy [[Delete]] dispatch and invariant validation."

  import QuickBEAM.VM.Heap.Keys, only: [proxy_target: 0]

  alias QuickBEAM.VM.{Heap, JSThrow}
  alias QuickBEAM.VM.ObjectModel.{OwnProperty, ProxyDispatch, ProxyTrap}
  alias QuickBEAM.VM.Semantics.Values

  def dispatch({:obj, ref} = proxy, key, fallback) when is_function(fallback, 2) do
    case Heap.get_obj(ref, %{}) do
      %{proxy_target() => _target} = proxy_map ->
        ProxyDispatch.with_trap(proxy_map, "deleteProperty", &fallback.(&1, key), fn target,
                                                                                     handler,
                                                                                     trap ->
          trap_result = trap |> ProxyTrap.call([target, key], handler) |> Values.truthy?()
          validate_invariant(target, key, trap_result)
        end)

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
        if OwnProperty.present?({:obj, target_ref}, key) and not Heap.extensible?(target_ref) do
          JSThrow.type_error!("proxy deleteProperty trap violates invariant")
        else
          true
        end
    end
  end

  def validate_invariant(_target, _key, result), do: result
end
