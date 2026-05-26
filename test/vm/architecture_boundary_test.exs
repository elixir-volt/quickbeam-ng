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

  @removed_builtin_dsl_patterns ~w(
    static_val
    proto_val
    symbol_method
    symbol_accessor
    symbol_getter
    species_accessor
    proto_symbol
    static_symbol
    install_methods_with
    install_hidden_static
  )

  test "runtime-facing VM code uses InternalMethods instead of low-level object model calls" do
    violations =
      @runtime_boundary_paths
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&forbidden_calls/1)

    assert violations == []
  end

  test "removed builtin DSL helpers do not reappear" do
    violations =
      ["lib", "test"]
      |> Enum.flat_map(&source_files/1)
      |> Enum.reject(&String.ends_with?(&1, "architecture_boundary_test.exs"))
      |> Enum.flat_map(&removed_builtin_dsl_references/1)

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
    scan_lines(path, fn line ->
      Enum.filter(@forbidden_runtime_calls, &String.contains?(line, &1))
    end)
  end

  defp removed_builtin_dsl_references(path) do
    scan_lines(path, fn line ->
      Enum.filter(@removed_builtin_dsl_patterns, &Regex.match?(~r/\b#{&1}\b/, line))
    end)
  end

  defp scan_lines(path, matcher) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      for match <- matcher.(line) do
        {path, line_number, match}
      end
    end)
  end
end
