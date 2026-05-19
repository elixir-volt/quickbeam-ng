defmodule QuickBEAM.VM.SpecTypes.Completion do
  @moduledoc """
  Documentation for QuickBEAM's representation of ECMA-262 Completion Records.

  Spec:
  - ECMA-262 §5.2.3 Completion Records

  QuickBEAM does not allocate completion-record structs in the hot interpreter or
  compiler paths. Instead:

  | Spec completion | QuickBEAM representation |
  |---|---|
  | normal completion | the raw VM value returned by a function/helper |
  | throw completion | `throw({:js_throw, value})` |
  | return/break/continue | QuickJS bytecode control-flow instructions and VM op handlers |

  This module is intentionally a terminology anchor for docs, tests, and audits.
  Runtime code should keep using the existing raw-value / throw representation.
  """

  @type normal(value) :: value
  @type throw_completion :: no_return()
  @type t(value) :: normal(value) | throw_completion()
end
