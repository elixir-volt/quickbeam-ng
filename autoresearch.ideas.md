## Remaining 4 failures (92→4, -95.7%)

All 4 are mismatches (0 unsupported, 157/157 compile, 153/157 native-loadable):

1. **Symbol.iterator for-of** — interpreter+BEAM return 3 (correct), native fails because for_of_start uses internal JS_ATOM_Symbol_iterator atom lookup which doesn't match our computed property key
2. **eval('arguments[0]')** — benchmark runs without runtime_pid so eval opcode can't compile strings; native also fails on scope setup
3. **Computed super destructuring** `({[p]: super.x} = {a:1})` — interpreter+BEAM return 1 (correct), native returns nil (put_super_value stack issue in native)
4. **test_language.js** — compiles (with stubs) but first assertion fails because stubbed function returns wrong value vs oracle errors on missing `gc` global

### Hard wall analysis
- Cases 1+3: interpreter/BEAM correct but native QuickJS bytecode incompatibility (fundamental atom/stack layout differences)
- Case 2: test infrastructure limitation (no runtime in benchmark)
- Case 4: complex multi-feature file with many stubbed functions
