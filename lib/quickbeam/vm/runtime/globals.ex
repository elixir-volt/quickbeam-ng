defmodule QuickBEAM.VM.Runtime.Globals do
  @moduledoc "JS global scope: constructors, global functions, and the binding map."

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.Runtime.WebAPIs

  alias QuickBEAM.VM.Runtime.{
    ArrayBufferInstaller,
    ArrayInstaller,
    CollectionInstaller,
    Console,
    CoreConstructorInstaller,
    DateInstaller,
    Errors,
    FunctionInstaller,
    GlobalFunctionInstaller,
    GlobalThisInstaller,
    JSON,
    Math,
    NumberInstaller,
    ObjectInstaller,
    ProxyInstaller,
    Reflect,
    RegExpInstaller,
    StringInstaller,
    Test262Host,
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

  defp bindings do
    %{
      "$262" => Test262Host.object(),
      "Array" => ArrayInstaller.constructor(),
      "String" => StringInstaller.constructor(),
      "Number" => NumberInstaller.constructor(),
      "Function" => FunctionInstaller.constructor(),
      "RegExp" => RegExpInstaller.constructor(),
      "Date" => DateInstaller.constructor(),
      "ArrayBuffer" => ArrayBufferInstaller.constructor(),
      "Proxy" => ProxyInstaller.constructor(),
      "Math" => Math.object() |> Math.install_metadata(),
      "JSON" => JSON.object() |> JSON.install_metadata(),
      "Reflect" => Reflect.object() |> Reflect.install_metadata(),
      "console" => Console.object()
    }
    |> Map.merge(GlobalFunctionInstaller.bindings())
    |> Map.merge(QuickBEAM.VM.Builtin.Discovery.bindings())
  end
end
