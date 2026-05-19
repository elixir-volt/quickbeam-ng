defmodule QuickBEAM.VM.SpecTypes.IteratorRecord do
  @moduledoc """
  Documentation for QuickBEAM iterator-record representations.

  Spec:
  - ECMA-262 §7.4 Operations on Iterator Objects
  - ECMA-262 §7.4.1 GetIterator
  - ECMA-262 §7.4.6 IteratorNext
  - ECMA-262 §7.4.11 IteratorClose

  QuickBEAM represents iterator state with VM values rather than a dedicated
  `%IteratorRecord{}` struct. Common forms include JavaScript iterator objects,
  `{:array_iter, object, index}`, `{:list_iter, list}`, and runtime-specific
  iterator objects created by built-ins.

  Shared spec-level behavior is implemented in `QuickBEAM.VM.Semantics.Iterators`.
  """
end
