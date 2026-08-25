# ADR 0003: readonly memoization stays hand-rolled

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
