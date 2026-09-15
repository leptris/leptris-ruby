# 25 — Scope-owned (iterparse) elements on the bulk/native read path

Status: DONE (1.9.174.5)

iterparse is moxml's streaming core, yet scope-owned elements
ride the FFI read path (two-call fetch + per-child Ruby wrap
frames; #4ca5b3c kept them off deliberately). The IterationScope
exposes exactly the seams the C faces read — @wrapper_cache
(reset per yield by new_subtree!, killing recycled-address
entries) and @version (advances per yield and on mutation) — so
the bulk children faces can take the SCOPE as their "document"
argument safely, provided the constructed wrappers are stamped
scope-aware: @structure_memoizable/@native_fast false,
@pub_document nil.

Pure address-based reads (fast_attribute / element text / name)
touch no cache — scope elements can use them via a construction
-time @addr_reads_fast that ignores scope ownership.

Gates: iterparse children/element_children identical via the C
path; identity holds within a yielded subtree and resets across
yields (the new_subtree! discipline); document stays nil for
scope yields; mutations on scope elements keep the Ruby path;
suite both modes.

## Outcome (1.9.174.5)

The bulk children faces take the IterationScope itself as their
"document" (its @wrapper_cache resets per yield via new_subtree!
— recycled pool addresses cannot collide — and its @version
advances per yield and on mutation); the C face stamps
scope-aware (@structure_memoizable/@native_fast false,
@pub_document nil) while document-owned stamps stay Qtrue.
Pure address-based reads (fast_attribute / element text / name)
switch to @addr_reads_fast — true for scope elements too (they
touch no cache). Mutations on scope elements keep the Ruby path.
Measured (load ~6): the 20k-record iterparse walk (attr + child
name + content per record) 124.8ms (FFI) -> 100.5ms (native
bulk) — ~20%.
