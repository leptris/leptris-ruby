# 37 — Document lazy Pointer + address-based xpath contexts

Status: DONE (1.9.174.10)

Documents still mint an FFI::Pointer eagerly (the parse/create
faces pay the funcall + one allocation + its GC visit per
document). Make #c_ptr lazy like Node's (attr_reader becomes a
materializer over @c_address), skip the Pointer in
build_binding_document, and feed the search paths Integer
addresses (the ffi gem converts Integers for :pointer params) so
per-xpath document Pointers never materialize at all.

Gates: c_ptr stability and public API unchanged; every FFI
document consumer still works (options paths, c14n, fragment
fallback); suite both modes.

## Outcome (1.9.174.10)

Document#c_ptr materializes lazily over @c_address (freed docs
answer nil — never re-materialize); build_binding_document skips
the Pointer funcall (one alloc + ~200ns per document). TRAP
FOUND: this ffi version does NOT convert Integers for typedef'd
pointer params — passing c_address into the compiled-eval calls
failed with ":pointer argument is not a valid pointer"; the
search paths keep passing the (now lazy, once-per-document)
Pointer. Also: replacing a mapped native.bundle in place gets
the next loader SIGKILLed (CODESIGNING Invalid Page) — the
vendoring cp is now an atomic cp+mv.
