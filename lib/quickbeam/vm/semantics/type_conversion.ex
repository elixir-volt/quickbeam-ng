defmodule QuickBEAM.VM.Semantics.TypeConversion do
  @moduledoc """
  ECMA-262 §7.1 Type Conversion abstract operations.

  This module is a spec-facing facade over the existing implementation modules.
  It is intended for discoverability and new semantic code; hot paths may keep
  calling the underlying modules directly where that is clearer or faster.
  """

  alias QuickBEAM.VM.Interpreter.Values.Coercion
  alias QuickBEAM.VM.ObjectModel.PropertyKey

  defdelegate to_number(value), to: Coercion
  defdelegate to_number(value, hint), to: Coercion
  defdelegate to_string(value), to: Coercion, as: :to_string_val
  defdelegate to_int32(value), to: Coercion
  defdelegate to_uint32(value), to: Coercion
  defdelegate to_primitive(value), to: Coercion
  defdelegate to_primitive(value, hint), to: Coercion
  defdelegate to_property_key(value), to: PropertyKey
end
