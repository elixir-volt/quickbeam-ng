defmodule QuickBEAM.Core.ContextSnapshotTest do
  use ExUnit.Case, async: true

  for mode <- [:beam, :beam_compiler] do
    @mode mode

    test "#{mode} context restores named heap snapshots" do
      {:ok, pool} = QuickBEAM.ContextPool.start_link(size: 1, mode: @mode)
      {:ok, ctx} = QuickBEAM.Context.start_link(pool: pool, apis: false)

      assert {:ok, 1} = QuickBEAM.Context.eval(ctx, "globalThis.harnessValue = 1")
      assert :ok = QuickBEAM.Context.snapshot(ctx, :harness)

      assert {:ok, 2} = QuickBEAM.Context.eval(ctx, "globalThis.harnessValue = 2")

      assert {:ok, "polluted"} =
               QuickBEAM.Context.eval(ctx, "Array.prototype.snapshotPollution = 'polluted'")

      assert :ok = QuickBEAM.Context.restore(ctx, :harness)
      assert {:ok, 1} = QuickBEAM.Context.eval(ctx, "globalThis.harnessValue")

      assert {:ok, "undefined"} =
               QuickBEAM.Context.eval(ctx, "typeof Array.prototype.snapshotPollution")

      assert {:ok, 3} =
               QuickBEAM.Context.eval(ctx, "globalThis.harnessValue = 3; harnessValue",
                 restore: :harness
               )

      assert {:ok, 1} = QuickBEAM.Context.eval(ctx, "globalThis.harnessValue", restore: :harness)
    end
  end

  test "NIF contexts report snapshots as unsupported" do
    {:ok, pool} = QuickBEAM.ContextPool.start_link(size: 1)
    {:ok, ctx} = QuickBEAM.Context.start_link(pool: pool, apis: false)

    assert {:error, :snapshots_not_supported} = QuickBEAM.Context.snapshot(ctx, :harness)
    assert {:error, :snapshots_not_supported} = QuickBEAM.Context.restore(ctx, :harness)
  end
end
