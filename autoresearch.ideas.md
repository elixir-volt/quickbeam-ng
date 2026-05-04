## Remaining 6 failures (92→6, -93.5%)

### Unsupported (1)
- `with(o){ delete x; }` — needs with-scope semantics: transform all variable accesses in body to `with_get_var`/`with_put_var`/`with_delete_var` with fallback targets. Interpreter already handles the opcodes.

### Mismatches (5)
- `Symbol.iterator` — interpreter+BEAM correct but native_load fails (native for_of_start uses internal atom JS_ATOM_Symbol_iterator which doesn't match our computed property key)
- `eval('arguments[0]')` — inherent indirect eval limitation
- Computed super destructuring `({[p]: super.x} = {a:1})` — interpreter+BEAM correct but native returns nil (subtle bytecode stack issue)
- Derived constructor `super(); return {x:1}` — all paths fail (super() via get_var doesn't resolve, factory path can't mark is_derived_class_constructor)
- `test_language.js` — compiles but assertion mismatch (stubbed functions return undefined vs oracle errors on `gc`)

### Hardest wall: native_load compatibility
3/5 mismatches are because native QuickJS interprets our bytecode differently (Symbol atoms, stack layouts, super semantics). These are fundamental native compatibility issues.
