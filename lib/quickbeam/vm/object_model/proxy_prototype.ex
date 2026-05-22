defmodule QuickBEAM.VM.ObjectModel.ProxyPrototype do
  @moduledoc "Proxy [[GetPrototypeOf]] dispatch."

  alias QuickBEAM.VM.ObjectModel.{ProxyDispatch, ProxyTrap}

  def get(proxy_map, fallback) when is_function(fallback, 1) do
    ProxyDispatch.with_trap(proxy_map, "getPrototypeOf", fallback, fn target, handler, trap ->
      ProxyTrap.call(trap, [target], handler)
    end)
  end
end
