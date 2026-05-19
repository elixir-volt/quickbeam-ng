defmodule QuickBEAM.VM.Semantics.ObjectOperations do
  @moduledoc """
  ECMA-262 §7.3 Operations on Objects and §10 object internal methods.

  This is a spec-facing facade over `QuickBEAM.VM.ObjectModel.*`. It gives docs,
  tests, and new semantic code stable names that correspond to ECMA abstract
  operations while preserving the existing implementation modules.
  """

  alias QuickBEAM.VM.ObjectModel.{Define, Delete, Get, HasProperty, OwnProperty, Put}

  defdelegate get(object, key), to: Get
  defdelegate set(object, key, value), to: Put, as: :put
  defdelegate delete_property_or_throw(object, key), to: Delete, as: :delete_property
  defdelegate has_property?(object, key), to: HasProperty
  defdelegate own_property_keys(object), to: OwnProperty, as: :own_keys
  defdelegate get_own_property(object, key), to: OwnProperty, as: :descriptor

  defdelegate define_property(object, key, descriptor_object, raw_descriptor),
    to: Define,
    as: :property
end
