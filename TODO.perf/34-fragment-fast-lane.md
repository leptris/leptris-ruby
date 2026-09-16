# 34 — Fragment fast lane: C parse, bulk children, one-shot markup append

Status: DONE (1.9.174.9)

The add_child(String) path — moxml's markup-builder shape — pays
three layers per call: parse_fragment_with_status allocates a
MemoryPointer for the status out-param, DocumentFragment#children
runs the FFI fetch+wrap loop (never moved to the bulk faces), and
each child appends through its own dispatch.

Bind the lane: a C parse face returns the fragment's address
(Integer — no Pointer, no MemoryPointer); the fragment stores
@c_address with a lazy c_ptr; children rides the bulk face
(fragment nodes live in the document pool — the document's cache
and version discipline apply); and a one-shot append face parses
the markup, walks the fragment's children, and appends every one
with a single readonly gate + version bump. Parse failures return
a marker; the Ruby fallback re-runs the old path for the exact
error message (the rare path, cheap to re-fail).

Gates: add_child(String) semantics identical (multiple top-level
nodes, text, PIs, namespaces lifted per the Node path); fragment
children identical through the bulk face; suite both modes.

## Outcome (1.9.174.9)

Three layers landed: the fragment parse face answers the
fragment ADDRESS (no status MemoryPointer, no Pointer mint —
failures fall back to the FFI pair for the exact error);
DocumentFragment stores @c_address with a lazy c_ptr and
children() rides the bulk face (fragment nodes live in the
document pool — the document's cache and version discipline
apply); and Element#add_child(String) runs ONE dispatch for the
whole markup add (parse + per-child append + single gate/bump —
with the move-during-iteration hazard caught by the suite:
appending detaches the child, so the walk captures next BEFORE
each move). -1 re-runs the legacy path for parse errors;
-1000-st routes through check_status. The markup row needs a
quiet-host battery number (this box sat at load 100+ today);
small-parse measured 6.8µs native vs 15.6µs FFI (~2.3x) under
load 100.
