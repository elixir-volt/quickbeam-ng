defmodule QuickBEAM.VM.Runtime.Globals do
  @moduledoc "JS global scope: constructors, global functions, and the binding map."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.Runtime.WebAPIs

  alias QuickBEAM.VM.Runtime.{
    CollectionInstaller,
    CoreConstructorInstaller,
    Errors,
    GlobalRegistry,
    GlobalThisInstaller,
    ObjectInstaller,
    TypedArrayInstaller
  }

  @doc "Builds the runtime value represented by this module."
  def build do
    {object_name, object_ctor} = ObjectInstaller.binding()

    bindings()
    |> Map.put(object_name, object_ctor)
    |> Map.merge(TypedArrayInstaller.bindings())
    |> Map.merge(CollectionInstaller.bindings())
    |> Map.merge(CoreConstructorInstaller.bindings())
    |> Map.merge(Errors.bindings())
    |> tap(&Heap.put_global_cache/1)
    |> Map.merge(WebAPIs.bindings())
    |> tap(&GlobalThisInstaller.install/1)
    |> tap(&Heap.put_global_cache/1)
  end

  # ── Binding map ──

  defp bindings, do: GlobalRegistry.bindings()
end
