defmodule QuickBEAM.VM.ObjectModel.ProxyOwnProperty do
  @moduledoc "Proxy [[GetOwnProperty]] dispatch and invariant validation."

  import QuickBEAM.VM.Heap.Keys, only: [proxy_handler: 0, proxy_target: 0]

  alias QuickBEAM.VM.{Heap, JSThrow, Value}
  alias QuickBEAM.VM.ObjectModel.{Get, ProxyTrap}

  def dispatch(proxy_map, prop_name, fallback, target_flags)
      when is_function(fallback, 2) and is_function(target_flags, 2) do
    target = Map.fetch!(proxy_map, proxy_target())
    handler = Map.fetch!(proxy_map, proxy_handler())

    cond do
      Map.get(proxy_map, "__proxy_revoked__") == true ->
        JSThrow.type_error!("Cannot perform operation on a revoked proxy")

      not Value.object_like?(handler) ->
        JSThrow.type_error!("Cannot perform operation on a proxy with null handler")

      true ->
        descriptor_trap(target, handler, prop_name, fallback, target_flags)
    end
  end

  def validate_result(target, prop_name, :undefined, target_flags)
      when is_function(target_flags, 2) do
    case target_flags.(target, prop_name) do
      %{configurable: false} ->
        invariant_error()

      nil ->
        :undefined

      _flags ->
        if target_extensible?(target), do: :undefined, else: invariant_error()
    end
  end

  def validate_result(target, prop_name, {:obj, result_ref} = result, target_flags)
      when is_function(target_flags, 2) do
    result_desc = Heap.get_obj(result_ref, %{})

    cond do
      not target_extensible?(target) and target_flags.(target, prop_name) == nil ->
        invariant_error()

      Map.get(result_desc, "configurable") == false and
          not match?(%{configurable: false}, target_flags.(target, prop_name)) ->
        invariant_error()

      Map.get(result_desc, "configurable") == false and Map.get(result_desc, "writable") == false and
          match?(%{writable: true}, target_flags.(target, prop_name)) ->
        invariant_error()

      true ->
        result
    end
  end

  def validate_result(_target, _prop_name, _result, _target_flags),
    do: JSThrow.type_error!("proxy getOwnPropertyDescriptor trap returned non-object")

  defp descriptor_trap(target, handler, prop_name, fallback, target_flags) do
    trap = Get.get(handler, "getOwnPropertyDescriptor")

    if Value.nullish?(trap) do
      fallback.(target, prop_name)
    else
      trap
      |> ProxyTrap.call([target, prop_name], handler)
      |> validate_result(target, prop_name, target_flags)
    end
  end

  defp target_extensible?({:obj, ref}), do: Heap.extensible?(ref)
  defp target_extensible?(_target), do: true

  defp invariant_error,
    do: JSThrow.type_error!("proxy getOwnPropertyDescriptor trap violates invariant")
end
