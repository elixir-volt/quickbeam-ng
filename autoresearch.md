# Autoresearch: JavaScript Parser Compatibility

## Objective
Close accepted-syntax compatibility gaps in the experimental hand-written JavaScript lexer/parser (`lib/quickbeam/js/parser*`) against QuickJS/Test262-style JavaScript while preserving VM/Web API behavior and the focused parser test suite.

This segment is compatibility-focused. Do not cheat by suppressing diagnostics, skipping validation, weakening tests, changing Test262 inputs, or special-casing benchmark files/strings. Fix the grammar/lexer behavior and add focused regression tests for each gap.

## Primary Metric
- **`test262_language_sample_errors`** (lower is better): total parser errors across the deterministic standalone non-negative `test/test262/test/**/*.js` corpus, excluding Test262 support fixtures after selecting the sample window.

## Secondary Metrics
- `test262_language_sample_error_files` — sampled files with parser errors.
- `test262_language_sample_unique_errors` — unique diagnostic messages in sampled files.
- `test262_language_sample_files` — sample size; default should stay 12000.
- `test262_language_sample_module_files` — files parsed with `source_type: :module` by metadata/static-module detection.
- `test_language_errors` — parser errors on `test/vm/test_language.js`; must stay 0.
- `test_language_parse_ok` — must stay 1.
- `quickjs_parser_tests` — QuickJS-port coverage signal; must not regress intentionally.
- `parser_tests` — focused parser test count.
- `parser_test_ms` — focused parser suite duration.

## Commands
Run the accepted-syntax compatibility loop with:

```sh
./autoresearch.sh
```

Run QuickJS-vs-parser acceptance parity with the generated ExUnit wrapper:

```sh
PARSER_BENCH=quickjs_audit_exunit AUDIT_OFFSET=30000 AUDIT_LIMIT=2000 ./autoresearch.sh
```

Useful optional environment variables:

```sh
TEST262_GLOB='test/test262/test/language/**/*.js' ./autoresearch.sh  # restrict accepted-syntax tests
TEST262_SAMPLE_OFFSET=20000 ./autoresearch.sh  # inspect a later accepted-syntax slice
TEST262_ERROR_LIMIT=80 ./autoresearch.sh       # print more accepted-syntax failing files
AUDIT_GLOB='test/test262/test/language/**/*.js' PARSER_BENCH=quickjs_audit_exunit ./autoresearch.sh
AUDIT_OFFSET=32000 AUDIT_LIMIT=2000 AUDIT_FILE_TIMEOUT=5000 PARSER_BENCH=quickjs_audit_exunit ./autoresearch.sh
```

`autoresearch.sh` runs:
1. `mix test test/js/parser --formatter ExUnit.CLIFormatter`
2. one selected benchmark:
   - `mix run bench/js_parser_compat.exs` for `PARSER_BENCH=compat`
   - `mix run bench/js_parser_perf.exs` for `PARSER_BENCH=perf`
   - `mix run bench/js_parser_quickjs_audit.exs` for legacy `PARSER_BENCH=quickjs_audit`
   - `mix test test/js/parser/quickjs_acceptance_audit_test.exs --only quickjs_acceptance_audit` for `PARSER_BENCH=quickjs_audit_exunit`

The benchmark prints:
- summary CSV rows for `test_language` and the Test262 sample
- top `ERROR_MESSAGE` clusters
- top `ERROR_DIR` clusters
- `ERROR_FILE ...` examples with source type and first diagnostic
- structured `METRIC ...` lines for autoresearch

## Source Type Rules
`bench/js_parser_compat.exs` parses files as modules when any of these are true:
- Test262 metadata has `flags: [... module ...]`
- path contains `/module-code/`, except fixtures whose filename explicitly marks `script-code`
- source has top-level-looking static `import` / `export` syntax

The deterministic sample excludes files ending in `_FIXTURE.js` after selecting the sample window because Test262 uses them as support inputs for other tests, not standalone accepted-syntax tests. Everything else is parsed as script source. This is benchmark setup only; do not edit Test262 files.

## Files in Scope
- `lib/quickbeam/js/parser.ex`
- `lib/quickbeam/js/parser/lexer.ex`
- `lib/quickbeam/js/parser/ast.ex`
- `lib/quickbeam/js/parser/token.ex`
- `lib/quickbeam/js/parser/error.ex`
- `test/js/parser/`
- `bench/js_parser_compat.exs`
- `autoresearch.sh`
- `autoresearch.md`

Benchmark inputs are read-only:
- `test/vm/test_language.js`
- `test/test262/test/language/**/*.js`

## Off Limits
- Zig/C/NIF files.
- External parser generators or native parser replacements.
- New dependencies for the parser compatibility loop.
- Benchmark overfitting or exact string/file special cases.

## Experiment Workflow
1. Run `./autoresearch.sh` or inspect current `ERROR_MESSAGE` / `ERROR_FILE` output.
2. Pick the broadest real syntax gap visible in the sample.
3. Add focused tests under `test/js/parser/<area>/..._test.exs` with `@moduletag :quickjs_port`.
4. Fix parser/lexer behavior generally.
5. Run `mix format`, `mix compile --warnings-as-errors`, `mix test test/js/parser`, then `./autoresearch.sh`.
6. Keep only changes that reduce the primary metric without regressing `test_language_errors`, parser tests, or QuickJS-port coverage.

## Current Known Gap Clusters
The full standalone non-negative Test262 corpus available in this checkout is parse-clean after excluding Test262 support fixtures. Inspect the current `ERROR_MESSAGE` and `ERROR_FILE` output before choosing any future gap.

If new Test262 files are added, rerun the benchmark and target a later slice using `TEST262_SAMPLE_OFFSET` if needed.
