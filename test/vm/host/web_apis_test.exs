defmodule QuickBEAM.VM.Host.WebAPIsTest do
  use ExUnit.Case, async: true

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.Host.{BeamAPI, Test262, WebAPIs}

  setup do
    Heap.reset()
    :ok
  end

  test "Beam bridge is a host API, not a Web namespace provider" do
    assert %{"Beam" => beam} = BeamAPI.bindings()
    assert {:obj, _} = beam
  end

  test "aggregated host bindings include Web APIs and Beam bridge" do
    bindings = WebAPIs.bindings()

    assert %{"Beam" => {:obj, _}} = bindings
    assert %{"URL" => _} = bindings
    assert %{"TextEncoder" => _} = bindings
    assert %{"setTimeout" => _} = bindings
  end

  test "Test262 host object is exposed from the host namespace" do
    assert {:obj, ref} = Test262.object()
    object = Heap.get_obj(ref)

    assert Map.has_key?(object, "createRealm")
    assert Map.has_key?(object, "detachArrayBuffer")
  end

  test "Test262 realms allocate distinct error intrinsics" do
    {:ok, rt} = QuickBEAM.start()

    on_exit(fn ->
      try do
        QuickBEAM.stop(rt)
      catch
        :exit, _ -> :ok
      end
    end)

    assert {:ok, "true|true"} =
             QuickBEAM.eval(
               rt,
               ~S<let g=$262.createRealm().global; [g.TypeError !== TypeError, g.TypeError.prototype !== TypeError.prototype].join("|")>,
               mode: :beam
             )
  end
end
