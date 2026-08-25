# ADR 0004: borrowed handles validate their lender

## Context
Before 1.9.5, only Document's own methods checked freed state:
`doc.free; node.name` read freed memory silently (verified
returning ""), stale mutations risked segfaults.

## Decision
`Node#ensure_alive!` guards every c_ptr-derefercing entry point —
after memo checks (memoized readonly results stay check-free) and
folded into `ensure_writable!` for mutations. The check is the
cheapest sufficient one: `Document#c_ptr.nil?` (#free nils it; the
GC finalizer cannot fire while any handle exists). `Document#freed?`
is the accurate public predicate.

## Consequences
Measured cost (harness, 1.9.4→1.9.6): visible only on the
single-cheapest call shape (Element#[] hot loops, ~13-28%); every
other loop at parity. Accepted as the price of the contract;
readonly hot loops have the memoized attributes/keys alternatives.
Do not re-litigate without a C-side lifetime mechanism.
