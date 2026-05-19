defmodule QuickBEAM.VM.SpecTypes.PropertyDescriptor do
  @moduledoc """
  Spec-facing alias for QuickBEAM property descriptor helpers.

  Spec:
  - ECMA-262 §6.2.6 The Property Descriptor Specification Type
  - ECMA-262 §10.1.6.3 ValidateAndApplyPropertyDescriptor

  The implementation lives in `QuickBEAM.VM.ObjectModel.PropertyDescriptor` and
  uses maps for descriptor records. This module exists so docs and audits can
  refer to the ECMA specification type directly while preserving the current
  representation.
  """

  defdelegate method(), to: QuickBEAM.VM.ObjectModel.PropertyDescriptor
  defdelegate accessor(), to: QuickBEAM.VM.ObjectModel.PropertyDescriptor
  defdelegate constructor(), to: QuickBEAM.VM.ObjectModel.PropertyDescriptor
  defdelegate prototype(), to: QuickBEAM.VM.ObjectModel.PropertyDescriptor
  defdelegate hidden_readonly(), to: QuickBEAM.VM.ObjectModel.PropertyDescriptor
end
