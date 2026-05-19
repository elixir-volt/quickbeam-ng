defmodule QuickBEAM.VM.Semantics.IteratorOperations do
  @moduledoc """
  ECMA-262 §7.4 Operations on Iterator Objects.

  Spec-facing facade over `QuickBEAM.VM.Semantics.Iterators`.
  """

  alias QuickBEAM.VM.Semantics.Iterators

  defdelegate get_iterator(value), to: Iterators, as: :for_of_start
  defdelegate iterator_next(iterator_next, iterator), to: Iterators, as: :for_of_next
  defdelegate iterator_next_result(next_fn, iterator, value), to: Iterators
  defdelegate iterator_close(iterator), to: Iterators
  defdelegate collect_iterator(iterator, next_fn), to: Iterators
  defdelegate iterator_result_object?(value), to: Iterators
end
