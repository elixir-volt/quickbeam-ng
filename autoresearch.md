# Autoresearch: VM Compiler Performance

## Objective
Improve invocation performance of the experimental BEAM compiler backend for QuickJS bytecode while preserving compiler/interpreter semantic parity and the widened strict Test262 compiler audit.

The workload is `PARSER_BENCH=vm_compiler_perf ./autoresearch.sh`, which benchmarks compiled invocation time against interpreter invocation time across representative VM compiler workloads.

## Metrics
- **Primary**: `compiler_avg_invoke_us` (µs, lower is better) — average compiled invocation time across benchmark workloads.
- **Secondary**:
  - `interpreter_avg_invoke_us` — interpreter comparison baseline for the same workloads.
  - `compiler_avg_speedup` — average interpreter/compiler speedup; higher is better.
  - `compiler_perf_workloads` — number of workloads included; should remain stable.
  - `quickjs_parser_tests`, `parser_tests`, `parser_test_ms` — backpressure signals emitted by the shared benchmark wrapper.

## How to Run

```sh
PARSER_BENCH=vm_compiler_perf ./autoresearch.sh
```

The benchmark emits per-workload diagnostics like:

```text
COMPILER_PERF workload=arithmetic_loop compile_us=... compiler_us=... interpreter_us=... speedup=...
```

and structured metrics:

```text
METRIC compiler_avg_invoke_us=...
METRIC interpreter_avg_invoke_us=...
METRIC compiler_avg_speedup=...
```

## Files in Scope

Compiler lowering and generated-BEAM performance:
- `lib/quickbeam/vm/compiler/lowering.ex`
- `lib/quickbeam/vm/compiler/lowering/builder.ex`
- `lib/quickbeam/vm/compiler/lowering/state.ex`
- `lib/quickbeam/vm/compiler/lowering/ops/*.ex`
- `lib/quickbeam/vm/compiler/optimizer.ex`
- `lib/quickbeam/vm/compiler/forms.ex`
- `lib/quickbeam/vm/compiler/runtime_helpers.ex`
- `lib/quickbeam/vm/compiler/runner.ex`
- `lib/quickbeam/vm/compiler/analysis/*.ex`

Benchmark and guardrails:
- `bench/vm_compiler_perf.exs`
- `bench/vm_compiler_semantic_gaps.exs`
- `bench/vm_compiler_test262.exs`
- `test/support/vm_compiler_audit.ex`
- `test/vm/compiler_test.exs`
- `test/vm/auto_mode_test.exs`

## Off Limits

- Do not weaken correctness checks, semantic audits, Test262 inputs, or benchmark assertions.
- Do not special-case benchmark workload strings or file names.
- Do not remove JS semantics to win microbenchmarks.
- Do not touch Zig/C/NIF code for this loop unless a measured Elixir-side bottleneck clearly requires it.
- Do not make compiler default-readiness changes in this loop; this target is invoke performance only.

## Constraints

- `mix compile --warnings-as-errors` must pass after code changes.
- `PARSER_BENCH=vm_compiler_semantics ./autoresearch.sh` must remain clean.
- `TEST262_LIMIT=1500 TEST262_CASE_TIMEOUT=5000 PARSER_BENCH=vm_compiler_test262 ./autoresearch.sh` should remain clean for kept changes.
- `./autoresearch.checks.sh` runs automatically after passing experiments and is authoritative.
- Keep improvements generic and architecture-driven.

## Current Baseline Context

Recent perf audit on `beam-vm-interpreter` after compiler correctness hardening:

```text
arithmetic_loop       speedup=0.897
array_sum             speedup=0.973
object_property_loop  speedup=0.989
closure_call          speedup=1.041
class_method          speedup=1.803
compiler_avg_invoke_us=50.737
interpreter_avg_invoke_us=79.174
compiler_avg_speedup=1.141
```

The simple arithmetic/array/object workloads are near parity or slightly slower, while class/method calls benefit most. Focus first on reducing compiled overhead in hot simple loops without regressing class/method gains.

## Promising Directions

- Inspect generated forms for simple loop workloads and remove avoidable helper calls, temporary binds, or context/global refreshes.
- Optimize block-call argument passing or stack/slot propagation where hot loops bounce through generated block functions.
- Specialize safe integer/number operations only when JS semantics are preserved; use runtime helpers when raw BEAM operations can raise or mis-handle `NaN`, infinities, negative zero, or BigInt.
- Reduce per-iteration global/property lookup overhead only with correct invalidation/freshness semantics.
- Consider benchmark instrumentation if per-workload metrics are not enough to localize regressions.

## What's Been Tried

- Correctness hardening brought strict selected Test262 compiler audit to 1582/1582 and semantic corpus to 1000/1000 before this performance loop.
- Prior arithmetic fixes intentionally routed risky operations through JS helpers for correctness; do not undo those unless a replacement preserves all JS edge cases.
