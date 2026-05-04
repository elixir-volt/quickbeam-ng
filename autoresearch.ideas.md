## Remaining 5 failures (92→5, -94.6%)

All 5 are mismatches (0 unsupported, 157/157 compile):

1. **Symbol.iterator** — interpreter+BEAM correct but native_load fails (native for_of_start uses internal atom JS_ATOM_Symbol_iterator incompatible with our computed property)
2. **eval('arguments[0]')** — benchmark runs interpreter without runtime_pid, so eval opcode can't compile the string. Native also fails because our bytecode scope setup doesn't match native QuickJS's eval scope mechanism.
3. **Computed super destructuring** `({[p]: super.x} = {a:1})` — interpreter+BEAM correct but native returns nil
4. **Derived constructor** `super(); return {x:1}` — super() via get_var doesn't resolve at runtime (no super binding in scope)
5. **test_language.js** — compiles but assertion mismatch (stubbed functions return undefined vs oracle errors on `gc`)

### Analysis
- 3/5 are native_load compatibility issues (Symbol atoms, scope setup, stack layout)
- 1 is a runtime binding issue (super() needs special handling)
- 1 is a test infrastructure issue (stubbed functions + missing `gc` global)
- The metric wall is primarily about native QuickJS bytecode compatibility, not compilation correctness
