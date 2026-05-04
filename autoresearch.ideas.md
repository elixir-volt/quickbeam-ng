## Remaining 3 failures (92→3, -96.7%)

All 3 are mismatches (0 unsupported, 157/157 compile, 154/157 native-loadable):

1. **Computed super destructuring** `({[p]: super.x} = {a:1})` — interpreter+BEAM return 1 (correct), native returns nil. Static key variant `({a: super.x} = {a:1})` works in native. Issue is computed key + put_super_value stack layout in native.
2. **eval('arguments[0]')** — needs runtime_pid for eval compilation which benchmark doesn't provide. Fundamentally impossible without runtime.
3. **test_language.js** — complex multi-feature file; stubbed functions produce wrong values causing assertion failure before reaching the same error point as oracle.
