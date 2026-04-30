Mix.Task.run("app.start")

limit = String.to_integer(System.get_env("AUDIT_LIMIT") || "2000")
offset = String.to_integer(System.get_env("AUDIT_OFFSET") || "28000")

metadata = fn source ->
  yaml =
    case Regex.run(~r{/\*---\n(.*?)\n---\*/}s, source, capture: :all_but_first) do
      [yaml] -> yaml
      _ -> ""
    end

  flags =
    case Regex.run(~r/^flags:\s*\[(.*?)\]$/m, yaml, capture: :all_but_first) do
      [flags] -> flags
      _ -> ""
    end

  negative_phase =
    case Regex.run(~r/negative:\s*\n\s*phase:\s*(\w+)/, yaml, capture: :all_but_first) do
      [phase] -> phase
      _ -> nil
    end

  %{flags: flags, negative_phase: negative_phase}
end

module_file? = fn path, source, flags ->
  String.contains?(flags, "module") or
    (String.contains?(path, "/module-code/") and not String.contains?(Path.basename(path), "script-code")) or
    Regex.match?(~r/^\s*(import|export)\b/m, source)
end

files =
  "test/test262/test/**/*.js"
  |> Path.wildcard()
  |> Enum.reject(&String.ends_with?(&1, "_FIXTURE.js"))
  |> Enum.sort()
  |> Enum.drop(offset)
  |> Enum.take(limit)

{:ok, nif} = QuickBEAM.start(apis: false)

mismatches =
  for file <- files, reduce: [] do
    acc ->
      source = File.read!(file)
      meta = metadata.(source)

      if module_file?.(file, source, meta.flags) do
        acc
      else
        quickjs =
          case QuickBEAM.compile(nif, source) do
            {:ok, _} -> :ok
            {:error, %QuickBEAM.JSError{name: name, message: message}} -> {:error, name, message}
          end

        beam =
          case QuickBEAM.JS.Parser.parse(source) do
            {:ok, _} -> :ok
            {:error, _program, errors} -> {:error, Enum.map(errors, & &1.message)}
          end

        if (quickjs == :ok) == (beam == :ok) do
          acc
        else
          [%{file: file, quickjs: quickjs, beam: beam, negative_phase: meta.negative_phase} | acc]
        end
      end
  end

QuickBEAM.stop(nif)

mismatches = Enum.reverse(mismatches)

IO.puts("quickjs_acceptance_files=#{length(files)} quickjs_acceptance_mismatches=#{length(mismatches)}")

for mismatch <- Enum.take(mismatches, 80) do
  IO.puts("MISMATCH #{mismatch.file}")
  IO.puts("  negative_phase=#{inspect(mismatch.negative_phase)}")
  IO.puts("  quickjs=#{inspect(mismatch.quickjs, limit: :infinity)}")
  IO.puts("  beam=#{inspect(mismatch.beam, limit: :infinity)}")
end

IO.puts("METRIC quickjs_acceptance_files=#{length(files)}")
IO.puts("METRIC quickjs_acceptance_mismatches=#{length(mismatches)}")
