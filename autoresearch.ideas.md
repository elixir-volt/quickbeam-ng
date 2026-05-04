## Remaining 6 failures (92→6, -93.5%)

### Unsupported (2)
- `with(o){ delete x; }` — needs with-scope semantics (`with_get_var`, `with_put_var`, `with_delete_var`)
- `test/vm/test_language.js` — needs `object_pattern_property` with AssignmentPattern defaults + declarations support for patterns with defaults

### Mismatches (4)
- `Symbol.iterator` custom iterable — interpreter's `for_of_start` doesn't call Symbol.iterator on custom objects
- `eval('arguments[0]')` — inherent limitation of indirect eval (no access to caller scope)
- Computed super destructuring `({[p]: super.x} = {a:1})` — native load fails (atom reference leak in bytecode writer)
- Derived constructor `super(); return {x:1}` — needs super() call support in define_class path + check_ctor_return runtime semantics

### Infrastructure added (not reducing failures yet)
- `check_ctor_return` opcode in assembler (ready for when super() works in define_class path)
- `bytecode_compiler_derived_ctor` flag for constructor return semantics
- Object destructuring default value pattern handler (ready for when declarations handle patterns)
- All unresolved identifiers emit `get_var` (prevents unknown globals from blocking compilation)
- Large integer handling (>Int32 → float constant)
