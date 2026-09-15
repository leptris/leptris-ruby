# 17 — Precomputed fast-path flags + set_attribute tightening

Status: DONE (1.9.163.7)

The native guards on hot paths are method chains:
native_fast_children? resolves as defined?(NATIVE_FAST) plus
scope_owned? (another method) — paid per mutation ([]=, add_child,
the insert family) and per cold read fill. @structure_memoizable
(TODO.perf/13) already carries "document-owned and alive" as an
ivar; NATIVE_FAST availability is fixed at load time before any
node exists, so the conjunction is construct-time constant.

Add @native_fast to every wrapper construction (Ruby initialize
and every C construction site): one ivar read replaces the chain
at every gate. Fold in the set_attribute shaves: the C face reads
attribute NAMES via StringValue+RSTRING_PTR (names cannot contain
NULs — same rationale as nn_attribute); VALUES keep StringValueCStr
so an embedded-NUL value still raises rather than truncating.

Gates: suite green in both modes (the FFI fallback semantics must
be unchanged for nodes constructed before a late native require —
worst case they stay on the FFI path); set_attribute row improves.

## Outcome (1.9.163.7)

@native_fast computed once at construction (Ruby initialize and
every C construction site — the bundle running implies the
constant), replacing the defined?+scope_owned? method chain at
every gate (native_fast?/native_fast_children? are ivar readers
now). []= additionally reads attribute names via
StringValue+RSTRING_PTR (values keep StringValueCStr — an
embedded-NUL value still raises; spec-pinned). Measured (load
17-31): binding []= 454ns mandate baseline -> 236ns (~2x on the
row; 0.88x vs Nokogiri's 209ns in the same run — effectively
parity).
