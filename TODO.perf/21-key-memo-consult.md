# 21 — key? consults the attribute memo

Status: DONE (1.9.174.3)

Element#key?/has_attribute? pays an engine FFI round-trip per
call even when the versioned @attr_values memo already proves
presence. Consult the memo first (hit = true; only a miss falls
through to the engine + written-name fallback — the memo cannot
prove ABSENCE for a partial fill).

Gates: key? true for memoized names, unchanged miss semantics
(undeclared-prefix fallback intact), readonly/namespace specs
green.

## Outcome (1.9.174.3)

Element#key? consults the versioned @attr_values memo first —
presence-proven hits skip the engine round-trip; partial-fill
misses still fall through to the engine + written-name fallback
(the memo cannot prove absence).
