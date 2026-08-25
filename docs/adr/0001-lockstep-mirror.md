# ADR 0001: ffi.rb mirrors the public header

## Context
ffi.rb attaches ~30 functions the binding never calls (typed
attribute accessors, copy-inserts, allocator hooks, xinclude
getters). Reviews keep proposing to strip them.

## Decision
Keep attaching every public-header symbol. The mirror makes the
attached-vs-exported audit (`nm -gU` on a fresh build) a drift
detector: when libleptris changes its surface, the audit fails
loudly instead of the binding silently missing ABI.

## Consequences
Attachment is declarative and cheap; unused functions cost nothing.
When a call site starts using a string-returning mirror function,
add it to the UTF8_RETURNS wrap-list (ADR 0002).
