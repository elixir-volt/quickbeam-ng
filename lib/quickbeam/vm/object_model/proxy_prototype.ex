defmodule QuickBEAM.VM.ObjectModel.ProxyPrototype do
  @moduledoc "Proxy [[GetPrototypeOf]] dispatch."

  alias QuickBEAM.VM.ObjectModel.{ProxyDispatch, ProxyTrap}

  def get(proxy_map, fallback) when is_function(fallback, 1) do
    {target, handler} = ProxyDispatch.target_handler!(proxy_map)
    get_trap(target, handler, fallback)
  end

  defp get_trap(target, handler, fallback) do
    trap = ProxyDispatch.trap(handler, "getPrototypeOf")

    if is_nil(ProxyDispatch.callable_trap!(trap, "getPrototypeOf")) do
      fallback.(target)
    else
      ProxyTrap.call(trap, [target], handler)
    end
  end
end
