# 24 — Immutable read lanes: line/byte_offset memo + precomputed public #document

Status: DONE (1.9.174.4)

Node#line and #byte_offset pay an FFI round-trip per call, but a
node's source position never changes — memoize unconditionally
(first read wins). The public Node#document walks scope_owned? (a
method chain) on every call though scope ownership is fixed at
construction — precompute @pub_document once (nil for
scope-owned) including at every C construction site.

Gates: line/byte_offset stable across mutations (they must be —
the engine reports source positions); document nil for
scope-owned yields exactly as before; suite both modes.

## Outcome (1.9.174.4)

line/byte_offset memoize unconditionally (a node's source
position never changes; 40ns hits). Node#document answers the
constructor-precomputed @pub_document (nil for scope-owned
yields) — the scope_owned? method chain disappears from one of
the most-called readers; every C construction site sets it.
