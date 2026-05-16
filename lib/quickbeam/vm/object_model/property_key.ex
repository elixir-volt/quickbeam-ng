defmodule QuickBEAM.VM.ObjectModel.PropertyKey do
  @moduledoc "Property key normalization and classification for JS object model."

  import QuickBEAM.VM.Value, only: [is_symbol: 1]

  alias QuickBEAM.VM.Interpreter.Values.Coercion

  @doc "Converts a JS value using ECMAScript ToPropertyKey semantics."
  def to_property_key(k) when is_binary(k), do: k
  def to_property_key({:symbol, "Symbol." <> _ = name, _ref}), do: {:symbol, name}
  def to_property_key(k) when is_symbol(k), do: k

  def to_property_key(k) do
    primitive = Coercion.to_primitive(k, "string")

    if is_symbol(primitive),
      do: primitive,
      else: QuickBEAM.VM.Interpreter.Values.stringify(primitive)
  end

  @doc "Normalize a JS value to a property key (string or symbol)."
  def normalize(k) when is_binary(k), do: k
  def normalize({:symbol, "Symbol." <> _ = name, _ref}), do: {:symbol, name}
  def normalize(k) when is_symbol(k), do: k
  def normalize(k) when is_integer(k) and k >= 0, do: Integer.to_string(k)
  def normalize(k) when is_float(k), do: QuickBEAM.VM.Interpreter.Values.stringify(k)
  def normalize({:tagged_int, n}), do: Integer.to_string(n)
  def normalize(k), do: QuickBEAM.VM.Interpreter.Values.stringify(k)

  @doc "Check if a key is a symbol."
  defguard is_symbol_key(k) when is_symbol(k)

  @max_array_index 4_294_967_294

  @doc "Try to parse a key as an ECMAScript array index."
  def array_index(k) when is_integer(k) and k >= 0 and k <= @max_array_index, do: {:ok, k}
  def array_index(k) when is_integer(k) and k >= 0, do: :error

  def array_index(k) when is_float(k) and k >= 0 and k <= @max_array_index and k == trunc(k),
    do: {:ok, trunc(k)}

  def array_index(k) when is_float(k) and k >= 0, do: :error

  def array_index(k) when is_binary(k) do
    case Integer.parse(k) do
      {idx, ""} when idx >= 0 and idx <= @max_array_index ->
        if Integer.to_string(idx) == k, do: {:ok, idx}, else: :error

      _ ->
        :error
    end
  end

  def array_index(_), do: :error

  def array_index?(key), do: match?({:ok, _}, array_index(key))
  def canonical_array_index?(key), do: array_index?(key)
  def integer_index?(key) when is_integer(key), do: key >= 0

  def integer_index?(key) when is_binary(key) do
    case Integer.parse(key) do
      {idx, ""} -> idx >= 0
      _ -> false
    end
  end

  def integer_index?(_), do: false

  @doc "Sorts own property keys in ECMAScript order while preserving string/symbol order."
  def sort_own_keys(keys) do
    {indexes, rest} = Enum.split_with(keys, &array_index?/1)
    {strings, symbols} = Enum.split_with(rest, &is_binary/1)

    Enum.sort_by(indexes, fn key ->
      {:ok, idx} = array_index(key)
      idx
    end)
    |> Enum.map(fn
      key when is_integer(key) -> Integer.to_string(key)
      key -> key
    end)
    |> Kernel.++(strings)
    |> Kernel.++(symbols)
  end
end
