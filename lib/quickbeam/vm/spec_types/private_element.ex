defmodule QuickBEAM.VM.SpecTypes.PrivateElement do
  @moduledoc """
  Documentation anchor for ECMA-262 private names/elements in QuickBEAM.

  Spec:
  - ECMA-262 §6.2.10 Private Names
  - ECMA-262 §10.1 PrivateField and PrivateMethod related operations
  - ECMA-262 §15.7 Classes

  QuickBEAM stores private-element state through the object-model private helpers
  rather than a public struct. See `QuickBEAM.VM.ObjectModel.Private` and class
  lowering/interpreter ops for the executable implementation.
  """
end
