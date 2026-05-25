defmodule QuickBEAM.VM.ArchitectureBoundaryTest do
  use ExUnit.Case, async: true

  @runtime_boundary_paths [
    "lib/quickbeam/vm/runtime",
    "lib/quickbeam/vm/interpreter",
    "lib/quickbeam/vm/semantics",
    "lib/quickbeam/vm/realm.ex"
  ]

  @forbidden_runtime_calls [
    "OwnProperty.descriptor(",
    "Prototype.get(",
    "Prototype.set(",
    "Define.property(",
    "Delete.property(",
    "HasProperty."
  ]

  test "runtime-facing VM code uses InternalMethods instead of low-level object model calls" do
    violations =
      @runtime_boundary_paths
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&forbidden_calls/1)

    assert violations == []
  end

  defp source_files(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.flat_map(&source_files(Path.join(path, &1)))

      true ->
        []
    end
  end

  defp forbidden_calls(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      for call <- @forbidden_runtime_calls, String.contains?(line, call) do
        {path, line_number, call}
      end
    end)
  end
end
