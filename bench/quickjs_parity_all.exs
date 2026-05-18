Mix.Task.run("app.start")

unless Code.ensure_loaded?(QuickBEAM.Test262) do
  Code.require_file("../test/support/test262.ex", __DIR__)
end

root = Path.join(QuickBEAM.Test262.root(), "test")

selected_categories =
  case System.get_env("TEST262_CATEGORY") do
    nil -> :all
    "" -> :all
    "all" -> :all
    value -> String.split(value, ",", trim: true)
  end

limit =
  case System.get_env("TEST262_LIMIT") do
    nil -> :infinity
    value -> String.to_integer(value)
  end

error_limit = String.to_integer(System.get_env("TEST262_ERROR_LIMIT", "40"))
case_timeout = String.to_integer(System.get_env("TEST262_CASE_TIMEOUT", "5000"))

files =
  case selected_categories do
    :all ->
      Path.join([root, "**/*.js"])
      |> Path.wildcard()

    categories ->
      Enum.flat_map(categories, &QuickBEAM.Test262.find_tests/1)
  end
  |> Enum.reject(&String.contains?(&1, "_FIXTURE"))
  |> Enum.sort()

files = if limit == :infinity, do: files, else: Enum.take(files, limit)

js_error? = fn
  {:error, %QuickBEAM.JS.Error{}} -> true
  {:error, {:js_throw, _}} -> true
  _ -> false
end

compiler_error? = fn
  {:error, {:beam_compiler_unsupported, _}} -> true
  {:error, {:beam_compiler_error, _}} -> true
  _ -> false
end

run_raw_case = fn full, mode ->
  {:ok, rt} = QuickBEAM.start(apis: false)

  try do
    case mode do
      :native -> QuickBEAM.eval(rt, full)
      mode -> QuickBEAM.eval(rt, full, mode: mode)
    end
  after
    QuickBEAM.stop(rt)
  end
end

run_with_timeout = fn fun ->
  task =
    Task.async(fn ->
      try do
        fun.()
      rescue
        error -> {:crash, {:error, error, __STACKTRACE__}}
      catch
        kind, reason -> {:crash, {kind, reason, __STACKTRACE__}}
      end
    end)

  case Task.yield(task, case_timeout + 1_000) || Task.shutdown(task, :brutal_kill) do
    {:ok, result} -> result
    nil -> {:timeout, case_timeout}
  end
end

run_case = fn source, meta, mode ->
  includes = Map.get(meta, "includes", [])
  flags = Map.get(meta, "flags", [])
  negative? = meta["negative"] != nil
  strict_prefix = if "onlyStrict" in flags, do: "\"use strict\";\n", else: ""
  full = strict_prefix <> QuickBEAM.Test262.harness_source(includes) <> "\n" <> source

  raw = run_with_timeout.(fn -> run_raw_case.(full, mode) end)

  cond do
    match?({:timeout, _}, raw) ->
      {:timeout, raw}

    match?({:crash, _}, raw) ->
      {:crash, raw}

    mode == :beam_compiler and compiler_error?.(raw) ->
      {:compiler_error, raw}

    negative? and js_error?.(raw) ->
      {:pass, raw}

    negative? ->
      {:fail, raw}

    match?({:ok, _}, raw) ->
      {:pass, raw}

    true ->
      {:fail, raw}
  end
end

skipped? = fn meta ->
  flags = Map.get(meta, "flags", [])
  "async" in flags or "module" in flags
end

results =
  Enum.map(files, fn file ->
    source = File.read!(file)
    meta = QuickBEAM.Test262.parse_metadata(source)
    relative = QuickBEAM.Test262.relative_path(file)

    if skipped?.(meta) do
      %{
        relative: relative,
        status: :skipped,
        native: :skipped,
        interpreter: :skipped,
        compiler: :skipped
      }
    else
      native = run_case.(source, meta, :native)

      if match?({:pass, _}, native) do
        interpreter = run_case.(source, meta, :beam)
        compiler = run_case.(source, meta, :beam_compiler)

        status =
          case {interpreter, compiler} do
            {{:pass, _}, {:pass, _}} -> :pass
            {{:pass, _}, {:compiler_error, _}} -> :compiler_error
            {{:pass, _}, {:timeout, _}} -> :compiler_timeout
            {{:pass, _}, {:crash, _}} -> :compiler_crash
            {{:pass, _}, {:fail, _}} -> :compiler_fail
            {{:fail, _}, {:pass, _}} -> :interpreter_fail_compiler_pass
            {{:fail, _}, {:fail, _}} -> :both_fail
            {{:timeout, _}, _} -> :interpreter_timeout
            {{:crash, _}, _} -> :interpreter_crash
            {{:compiler_error, _}, _} -> :interpreter_infra_error
            _ -> :mismatch
          end

        %{
          relative: relative,
          status: status,
          native: native,
          interpreter: interpreter,
          compiler: compiler
        }
      else
        %{
          relative: relative,
          status: :native_rejected,
          native: native,
          interpreter: :not_run,
          compiler: :not_run
        }
      end
    end
  end)

summary = Enum.frequencies_by(results, & &1.status)
count = fn status -> Map.get(summary, status, 0) end
accepted = Enum.reject(results, &(&1.status in [:native_rejected, :skipped]))
failures = Enum.reject(accepted, &(&1.status == :pass))

IO.puts(
  "quickjs_parity_all_cases=#{length(results)} quickjs_parity_all_native_accepted=#{length(accepted)} quickjs_parity_all_pass=#{count.(:pass)} quickjs_parity_all_failures=#{length(failures)} quickjs_parity_all_native_rejected=#{count.(:native_rejected)} quickjs_parity_all_skipped=#{count.(:skipped)}"
)

for result <- Enum.take(failures, error_limit) do
  IO.puts("QUICKJS_PARITY_ALL_#{String.upcase(to_string(result.status))} #{result.relative}")
  IO.puts("  native=#{inspect(result.native, limit: 80)}")
  IO.puts("  interpreter=#{inspect(result.interpreter, limit: 80)}")
  IO.puts("  compiler=#{inspect(result.compiler, limit: 80)}")
end

IO.puts("METRIC quickjs_parity_all_cases=#{length(results)}")
IO.puts("METRIC quickjs_parity_all_native_accepted=#{length(accepted)}")
IO.puts("METRIC quickjs_parity_all_pass=#{count.(:pass)}")
IO.puts("METRIC quickjs_parity_all_failures=#{length(failures)}")
IO.puts("METRIC quickjs_parity_all_native_rejected=#{count.(:native_rejected)}")
IO.puts("METRIC quickjs_parity_all_skipped=#{count.(:skipped)}")
IO.puts("METRIC compiler_errors=#{count.(:compiler_error)}")
IO.puts("METRIC compiler_timeouts=#{count.(:compiler_timeout)}")
IO.puts("METRIC compiler_crashes=#{count.(:compiler_crash)}")
IO.puts("METRIC compiler_fails=#{count.(:compiler_fail)}")
IO.puts("METRIC both_fail=#{count.(:both_fail)}")
IO.puts("METRIC interpreter_fail_compiler_pass=#{count.(:interpreter_fail_compiler_pass)}")
IO.puts("METRIC interpreter_timeouts=#{count.(:interpreter_timeout)}")
IO.puts("METRIC interpreter_crashes=#{count.(:interpreter_crash)}")
