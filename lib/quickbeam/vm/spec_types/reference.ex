defmodule QuickBEAM.VM.SpecTypes.Reference do
  @moduledoc """
  Documentation for QuickBEAM's representation of ECMA-262 Reference Records.

  Spec:
  - ECMA-262 §6.2.7 The Reference Record Specification Type

  QuickJS bytecode has already lowered most syntactic references to local slots,
  closure cells, global opcodes, or property-access opcodes before BEAM execution.
  QuickBEAM therefore does not keep a general `%Reference{}` value in the hot
  path. Observable Reference Record behavior is implemented across:

  - `QuickBEAM.VM.GlobalEnv` for global bindings
  - `QuickBEAM.VM.ObjectModel.Get` / `Put` / `Delete` for property references
  - interpreter/compiler local-slot and capture-cell operations
  - strict-assignment and TDZ checks in bytecode op handlers/runtime helpers

  This module is a spec terminology anchor, not a runtime data structure.
  """
end
