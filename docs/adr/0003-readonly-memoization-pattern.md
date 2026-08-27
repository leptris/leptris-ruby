# ADR 0003: memoization stays hand-rolled; writable docs memoize via version stamps

## 2026-08-27 extension (leptris-ruby 1.9.14)

Writable documents now memoize too: Document carries a mutation
version advanced at every mutation gate (Node#ensure_writable!,
root=, add_pi), and each memoized field stores its OWN version
stamp (`return @x if memo_hit?(@x_version)`). A shared node-level
stamp was tried and rejected — one field's recompute resurrects
another field's stale memo. Readonly semantics are unchanged
(their version never advances). Round X's "version-stamp rejected:
the compare costs the read" was corrected: the compare is cheap
against multi-FFI reads.

The hand-rolled per-site pattern (below) still stands; only the
guard gained a version argument.


## Context
Every readonly-mode read repeats the same three lines:
`return @x if readonly_cached?(:@x); v = compute; @x = v if
@document&.readonly?`. ~25 sites. Reviews keep proposing a
`readonly_memo(ivar) { }` concentrator.

## Decision
Keep the pattern hand-rolled. Concentrating it requires
instance_variable_get/set — banned project-wide (encapsulation:
no reaching into another object's ivars, and metaprogrammed ivar
access hides the memo identity from readers).

## Consequences
The repetition IS the invariant — greppable, one file at a time.
New readonly reads copy the three lines verbatim; a site that
deviates is visible in review.
