#!/usr/bin/env bash
set -euo pipefail

bytecode_test_output=$(mix test test/js/bytecode_compiler_test.exs --formatter ExUnit.CLIFormatter 2>&1)
printf '%s\n' "$bytecode_test_output"

case "${JS_BYTECODE_BENCH:-existing}" in
  existing)
    bench_output=$(mix run bench/js_bytecode_compiler_existing_corpus.exs 2>&1)
    ;;
  frontier)
    bench_output=$(mix run bench/js_bytecode_compiler_frontier.exs 2>&1)
    ;;
  *)
    echo "unknown JS_BYTECODE_BENCH=${JS_BYTECODE_BENCH}" >&2
    exit 2
    ;;
esac

printf '%s\n' "$bench_output"

compat_output=$(mix run bench/js_bytecode_compiler_compat.exs 2>&1)
printf '%s\n' "$compat_output"

printf '%s\n' "$bench_output" | grep '^METRIC '
printf '%s\n' "$compat_output" | grep '^METRIC '
