defmodule QuickBEAM.VM.ECMAMetadataTest do
  use ExUnit.Case, async: true

  @section_file Path.expand("../support/ecma_sections.txt", __DIR__)
  @valid_sections @section_file |> File.read!() |> String.split("\n", trim: true) |> MapSet.new()
  @runtime_files Path.wildcard("lib/quickbeam/vm/runtime/**/*.ex") ++
                   Path.wildcard("lib/quickbeam/vm/runtime.ex")

  @proposal_or_host_declarations [
    {QuickBEAM.VM.Runtime.Map, :proto_property_meta, "getOrInsert"},
    {QuickBEAM.VM.Runtime.Map, :proto_property_meta, "getOrInsertComputed"},
    {QuickBEAM.VM.Runtime.Iterator, :static_property_meta, "concat"},
    {QuickBEAM.VM.Runtime.Iterator, :static_property_meta, "zip"},
    {QuickBEAM.VM.Runtime.Iterator, :static_property_meta, "zipKeyed"}
  ]

  test "runtime @ecma annotations point at known ECMA-262 sections" do
    invalid =
      for file <- @runtime_files,
          {line, line_number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          [section] <- Regex.scan(~r/@ecma\s+"([^"]+)"/, line, capture: :all_but_first),
          not MapSet.member?(@valid_sections, section),
          do: {file, line_number, section}

    assert invalid == []
  end

  test "proposal and host declarations stay out of ECMA metadata" do
    for {module, function, key} <- @proposal_or_host_declarations do
      assert %{ecma: nil} = apply(module, function, [key])
    end

    raw_json = QuickBEAM.VM.Runtime.JSON.object() |> elem(2) |> Map.fetch!("rawJSON")
    is_raw_json = QuickBEAM.VM.Runtime.JSON.object() |> elem(2) |> Map.fetch!("isRawJSON")
    sum_precise = QuickBEAM.VM.Runtime.Math.object() |> elem(2) |> Map.fetch!("sumPrecise")

    assert %{ecma: nil} = QuickBEAM.VM.Builtin.metadata_for(raw_json)
    assert %{ecma: nil} = QuickBEAM.VM.Builtin.metadata_for(is_raw_json)
    assert %{ecma: nil} = QuickBEAM.VM.Builtin.metadata_for(sum_precise)
  end
end
