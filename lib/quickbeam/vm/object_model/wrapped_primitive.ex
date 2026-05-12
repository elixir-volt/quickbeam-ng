defmodule QuickBEAM.VM.ObjectModel.WrappedPrimitive do
  @moduledoc "Helpers for boxed primitive object slots."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.Runtime.Constructors

  @slots %{
    string: "__wrapped_string__",
    number: "__wrapped_number__",
    boolean: "__wrapped_boolean__",
    bigint: "__wrapped_bigint__",
    symbol: "__wrapped_symbol__"
  }

  @constructors %{
    string: "String",
    number: "Number",
    boolean: "Boolean",
    bigint: "BigInt"
  }

  @tags %{
    string: "String",
    number: "Number",
    boolean: "Boolean"
  }

  def slot(type), do: Map.fetch!(@slots, type)

  def type_for_value(value) when is_binary(value), do: :string
  def type_for_value(value) when is_number(value), do: :number
  def type_for_value(value) when is_boolean(value), do: :boolean
  def type_for_value({:bigint, _}), do: :bigint
  def type_for_value({:symbol, _}), do: :symbol
  def type_for_value({:symbol, _, _}), do: :symbol
  def type_for_value(_), do: nil

  def wrap(value) do
    case type_for_value(value) do
      nil -> value
      type -> wrap(type, value)
    end
  end

  def wrap(:symbol, value), do: Heap.wrap(%{slot(:symbol) => value})

  def wrap(type, value) do
    slot = slot(type)

    data =
      case Map.fetch(@constructors, type) do
        {:ok, constructor_name} ->
          case Constructors.class_proto(constructor_name) do
            {:obj, _} = proto -> %{slot => value, "__proto__" => proto}
            _ -> %{slot => value}
          end

        :error ->
          %{slot => value}
      end

    Heap.wrap(data)
  end

  def type(map) when is_map(map) do
    Enum.find_value(@slots, fn {type, slot} ->
      if Map.has_key?(map, slot), do: type
    end)
  end

  def type(_), do: nil

  def value(map) when is_map(map) do
    case type(map) do
      nil -> :error
      type -> {:ok, Map.fetch!(map, slot(type))}
    end
  end

  def value(_), do: :error

  def value(map, type) when is_map(map) do
    case Map.fetch(map, slot(type)) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  def value(_, _), do: :error

  def tag(map) when is_map(map) do
    case type(map) do
      nil -> nil
      type -> Map.get(@tags, type)
    end
  end

  def tag(_), do: nil
end
