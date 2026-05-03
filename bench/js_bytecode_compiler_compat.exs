Mix.Task.run("app.start")
Code.require_file("support/common.exs", __DIR__)
Code.require_file("../test/support/js_bytecode_compiler_audit.ex", __DIR__)

results = QuickBEAM.JS.BytecodeCompilerAudit.run()
summary = QuickBEAM.JS.BytecodeCompilerAudit.summary(results)

IO.puts(
  "js_bytecode_compiler_cases=#{summary.cases} js_bytecode_compiler_compiled=#{summary.compiled} js_bytecode_compiler_unsupported=#{summary.unsupported} js_bytecode_compiler_mismatches=#{summary.mismatches} js_bytecode_compiler_native_loadable=#{summary.native_loadable} js_bytecode_compiler_failures=#{summary.failures}"
)

for result <- results, result.status != :pass do
  IO.puts("JS_BYTECODE_COMPILER_#{String.upcase(to_string(result.status))} #{result.name}")
  IO.puts("  source=#{result.source}")
  IO.puts("  expected=#{inspect(result.expected)}")
  IO.puts("  interpreter=#{inspect(Map.get(result, :interpreter))}")
  IO.puts("  compiler=#{inspect(Map.get(result, :compiler))}")
  IO.puts("  native_load=#{inspect(Map.get(result, :native_load))}")
  IO.puts("  reason=#{inspect(Map.get(result, :reason))}")
end

Bench.Support.metrics(
  js_bytecode_compiler_cases: summary.cases,
  js_bytecode_compiler_compiled: summary.compiled,
  js_bytecode_compiler_unsupported: summary.unsupported,
  js_bytecode_compiler_mismatches: summary.mismatches,
  js_bytecode_compiler_native_loadable: summary.native_loadable,
  js_bytecode_compiler_failures: summary.failures
)

if summary.failures != 0, do: System.halt(1)
