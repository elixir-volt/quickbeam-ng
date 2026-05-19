defmodule QuickBEAM.VM.Semantics.Comparison do
  @moduledoc """
  ECMA-262 §7.2 Testing and Comparison Operations.

  Facade over QuickBEAM's equality, relational comparison, and SameValue helpers.
  """

  alias QuickBEAM.VM.Interpreter.Values.{Comparison, Equality}
  alias QuickBEAM.VM.ObjectModel.Semantics

  defdelegate is_loosely_equal(left, right), to: Equality, as: :eq
  defdelegate is_strictly_equal(left, right), to: Equality, as: :strict_eq
  defdelegate abstract_relational_less_than(left, right), to: Comparison, as: :lt
  defdelegate abstract_relational_less_than_or_equal(left, right), to: Comparison, as: :lte
  defdelegate abstract_relational_greater_than(left, right), to: Comparison, as: :gt
  defdelegate abstract_relational_greater_than_or_equal(left, right), to: Comparison, as: :gte
  defdelegate same_value?(left, right), to: Semantics
end
