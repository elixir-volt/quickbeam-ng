defmodule QuickBEAM.VM.Runtime.Globals do
  @moduledoc "JS global scope: constructors, global functions, and the binding map."

  alias QuickBEAM.VM.Runtime.GlobalBuilder

  @doc "Builds the runtime value represented by this module."
  def build, do: GlobalBuilder.build()
end
