defmodule QuickBEAM.VM.Execution.RegexpState do
  @moduledoc "Process-local mutable own-property state for RegExp values backed by bytecode tuples."

  def get(ref), do: Process.get(key(ref), %{})

  def fetch(ref, property), do: Map.fetch(get(ref), property)

  def put(ref, property, value) do
    Process.put(key(ref), Map.put(get(ref), property, value))
    :ok
  end

  def has_property?(ref, property), do: Map.has_key?(get(ref), property)

  defp key(ref), do: {:qb_regexp_props, ref}
end
