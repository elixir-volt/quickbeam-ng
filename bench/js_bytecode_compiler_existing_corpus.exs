Code.require_file("../test/support/js_bytecode_compiler_audit.ex", __DIR__)
Code.require_file("../test/support/vm_compiler_audit.ex", __DIR__)

limit = String.to_integer(System.get_env("JS_BYTECODE_EXISTING_LIMIT", "120"))
offset = String.to_integer(System.get_env("JS_BYTECODE_EXISTING_OFFSET", "0"))
failure_limit = String.to_integer(System.get_env("JS_BYTECODE_EXISTING_FAILURE_LIMIT", "20"))

quickbeam_vm_cases =
  QuickBEAM.VM.CompilerAudit.cases() ++ QuickBEAM.VM.CompilerAudit.corpus_cases()

file_cases = [
  {"test/vm/test_language.js", File.read!("test/vm/test_language.js")}
]

cases =
  (quickbeam_vm_cases ++ file_cases)
  |> Enum.uniq_by(fn {_name, source} -> source end)
  |> Enum.slice(offset, limit)

results = QuickBEAM.JS.BytecodeCompilerAudit.run(cases)
summary = QuickBEAM.JS.BytecodeCompilerAudit.summary(results)

IO.puts(
  "js_bytecode_existing_cases=#{summary.cases} " <>
    "js_bytecode_existing_compiled=#{summary.compiled} " <>
    "js_bytecode_existing_unsupported=#{summary.unsupported} " <>
    "js_bytecode_existing_mismatches=#{summary.mismatches} " <>
    "js_bytecode_existing_native_loadable=#{summary.native_loadable} " <>
    "js_bytecode_existing_failures=#{summary.failures}"
)

results
|> Enum.reject(&(&1.status == :pass))
|> Enum.take(failure_limit)
|> Enum.each(fn result ->
  IO.puts("JS_BYTECODE_EXISTING_#{String.upcase(to_string(result.status))} #{result.name}")
  IO.puts("  source=#{String.slice(result.source, 0, 500)}")
  IO.puts("  expected=#{inspect(Map.get(result, :expected))}")
  IO.puts("  interpreter=#{inspect(Map.get(result, :interpreter))}")
  IO.puts("  compiler=#{inspect(Map.get(result, :compiler))}")
  IO.puts("  native_load=#{inspect(Map.get(result, :native_load))}")
  IO.puts("  reason=#{inspect(Map.get(result, :reason))}")
end)

IO.puts("METRIC js_bytecode_existing_cases=#{summary.cases}")
IO.puts("METRIC js_bytecode_existing_compiled=#{summary.compiled}")
IO.puts("METRIC js_bytecode_existing_unsupported=#{summary.unsupported}")
IO.puts("METRIC js_bytecode_existing_mismatches=#{summary.mismatches}")
IO.puts("METRIC js_bytecode_existing_native_loadable=#{summary.native_loadable}")
IO.puts("METRIC js_bytecode_existing_failures=#{summary.failures}")
