# Autoresearch: JS Bytecode Compiler Existing Corpus

## Objective
Expand the separate frontend compiler using existing QuickBEAM/QuickJS-style test cases as the main workload:

```text
QuickBEAM.JS.Parser AST -> QuickBEAM.JS.BytecodeCompiler -> %QuickBEAM.VM.Bytecode{} -> QuickBEAM.VM.Bytecode.Writer -> QuickJS-loadable bytecode binary
```

The primary benchmark is corpus-driven, not hand-curated. It draws JavaScript programs from existing QuickBEAM VM compiler audits and existing JS files, then uses QuickJS through QuickBEAM as the semantic oracle. The curated frontier remains available as a secondary diagnostic mode, but the default loop optimizes the existing corpus metric.

Do not cheat by special-casing benchmark strings, suppressing unsupported errors, editing existing test inputs to make the metric easier, bypassing QuickJS validation, or fabricating loadability. Fix generic bytecode compiler, writer, scope, or VM semantics.

## Primary Metric
- **`js_bytecode_existing_failures`** (lower is better): failures across existing QuickBEAM JS/VM corpus cases. Failure means unsupported compiler feature, compiler error, semantic mismatch against QuickJS, BEAM compiler mismatch, interpreter mismatch, or emitted binary not QuickJS-loadable with the expected result.

## Secondary Metrics
- `js_bytecode_existing_cases` — selected corpus window size.
- `js_bytecode_existing_compiled` — existing corpus cases that compile to `%QuickBEAM.VM.Bytecode{}`.
- `js_bytecode_existing_unsupported` — compiler gaps returning `{:unsupported, ...}`.
- `js_bytecode_existing_mismatches` — compiled cases that disagree with QuickJS/interpreter/BEAM compiler/native-load.
- `js_bytecode_existing_native_loadable` — compiled corpus cases whose emitted binary loads through QuickJS with the expected result.
- `js_bytecode_compiler_cases` — stable regression audit size.
- `js_bytecode_compiler_failures` — must stay `0`.
- `js_bytecode_compiler_mismatches` — must stay `0`.
- `js_bytecode_compiler_native_loadable` — must equal `js_bytecode_compiler_cases`.
- Diagnostic-only frontier metrics are available when running `JS_BYTECODE_BENCH=frontier`.

## Commands
Run the default existing-corpus loop with:

```sh
./autoresearch.sh
```

Useful options:

```sh
JS_BYTECODE_EXISTING_LIMIT=200 ./autoresearch.sh
JS_BYTECODE_EXISTING_OFFSET=120 ./autoresearch.sh
JS_BYTECODE_EXISTING_FAILURE_LIMIT=30 ./autoresearch.sh
JS_BYTECODE_BENCH=frontier ./autoresearch.sh
```

`autoresearch.sh` runs:

1. `mix test test/js/bytecode_compiler_test.exs`
2. default: `mix run bench/js_bytecode_compiler_existing_corpus.exs`
   - optional diagnostic: `JS_BYTECODE_BENCH=frontier mix run bench/js_bytecode_compiler_frontier.exs`
3. `mix run bench/js_bytecode_compiler_compat.exs`

All scripts emit structured `METRIC name=value` lines.

## QuickJS / Existing Test Infrastructure
Rely on existing tests as much as possible:

- Existing QuickBEAM VM compiler audit cases are imported from:
  ```text
  test/support/vm_compiler_audit.ex
  ```
- Existing JS files include:
  ```text
  test/vm/test_language.js
  ```
- The stable frontend compiler audit remains in:
  ```text
  test/support/js_bytecode_compiler_audit.ex
  ```

For every selected source string:

1. `QuickBEAM.eval/2` gives the native QuickJS oracle.
2. `QuickBEAM.JS.BytecodeCompiler.compile/1` attempts frontend compilation.
3. If compilation succeeds, all execution paths must match QuickJS:
   ```elixir
   QuickBEAM.VM.Interpreter.eval(...)
   QuickBEAM.VM.Compiler.invoke(...)
   QuickBEAM.load_bytecode(rt, binary)
   ```

This validates semantics and bytecode serialization, not just parser acceptance. Test262 can be added as another existing-corpus mode later using filtered executable windows plus harness handling; do not run a noisy monolithic Test262 sweep as the default until harness/module/async filtering is explicit.

## Files in Scope
- `lib/quickbeam/js/bytecode_compiler.ex` — public API/orchestration.
- `lib/quickbeam/js/bytecode_compiler/*.ex` — compiler passes, emitter, scope, assembler.
- `lib/quickbeam/vm/bytecode.ex` — neutral bytecode structures.
- `lib/quickbeam/vm/bytecode/writer.ex` — QuickJS binary serialization.
- `lib/quickbeam/vm/opcodes.ex` — opcode metadata boundary only if required.
- `lib/quickbeam/vm/compiler/**` — only for real BEAM-compiler mismatches exposed by compiled bytecode.
- `lib/quickbeam/vm/interpreter/**` — only for real interpreter mismatches exposed by compiled bytecode.
- `test/js/bytecode_compiler_test.exs` — focused regression tests.
- `test/support/js_bytecode_compiler_audit.ex` — stable compatibility audit.
- `test/support/vm_compiler_audit.ex` — existing corpus source, read-only unless fixing reusable audit helpers.
- `bench/js_bytecode_compiler_existing_corpus.exs` — default existing-corpus benchmark.
- `bench/js_bytecode_compiler_frontier.exs` — diagnostic frontier benchmark.
- `bench/js_bytecode_compiler_compat.exs` — stable frontend regression audit.
- `autoresearch.sh`, `autoresearch.md`, `autoresearch.checks.sh`, `autoresearch.ideas.md`.

## Off Limits
- Do not modify QuickJS/Test262/QuickBEAM test inputs to improve the metric.
- Do not couple `QuickBEAM.JS.BytecodeCompiler` to `QuickBEAM.VM.Compiler` internals.
- Do not make the existing VM compiler the frontend compiler.
- Do not default-enable experimental compiler paths globally.
- Do not add external parser/compiler dependencies.
- Do not weaken `mix lint`, ExDNA clone budget, or warning settings.
- Do not special-case exact existing corpus source strings or names.

## Constraints
- Preserve existing stable audit cleanliness:
  ```text
  js_bytecode_compiler_failures=0
  js_bytecode_compiler_mismatches=0
  js_bytecode_compiler_native_loadable=js_bytecode_compiler_cases
  ```
- Keep emitted binaries QuickJS-loadable.
- Use QuickJS as reference but write idiomatic Elixir.
- Keep the compiler namespace separate:
  ```text
  QuickBEAM.JS.BytecodeCompiler
  ```
- Shared boundaries with existing VM compiler should remain limited to neutral bytecode/opcode/writer infrastructure unless fixing a real VM compiler mismatch.

## Current Existing-Corpus Themes
The default corpus includes existing QuickBEAM VM compiler cases and corpus cases. It naturally emphasizes:

- arithmetic/coercion breadth;
- existing VM language semantics;
- functions, recursion, closures;
- arrays/objects/methods;
- classes/constructors;
- destructuring/spread/rest/default parameters;
- switch/try/catch/finally;
- loops/iterators;
- operators not yet supported by the frontend compiler.

When a cluster is fixed, add focused tests and move representative cases into `test/support/js_bytecode_compiler_audit.ex` so they become permanent stable frontend coverage.

## What's Been Tried
- Existing compiler work reached a clean 53-case stable frontend audit before this existing-corpus phase.
- A small hand-curated frontier benchmark was created first; it remains available as `JS_BYTECODE_BENCH=frontier` but is no longer the default optimization target.
- The frontend compiler already supports literals, locals, assignments, compound/update assignments, arithmetic/comparison/unary/logical/sequence expressions, conditionals, `if`, `while`, `do while`, `for`, `break`/`continue`, functions, returns, generic calls, arrays, object literals, shorthand/computed keys, property reads/writes, computed writes, method calls, basic `this`, and QuickJS-loadable binary output.
- Existing BEAM compiler shaped-object stale reads after writes were fixed by invalidating shaped object slot types after compiled `put_field` / `put_array_el`.
