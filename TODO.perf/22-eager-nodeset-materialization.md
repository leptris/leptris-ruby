# 22 — Eager-in-C nodeset materialization (drop the per-call AutoPointer)

Status: DONE (1.9.174.4)

Every xpath() nodeset result pays an FFI::AutoPointer + a Method
object + finalizer registration (~400-600ns plus their GC) just
to keep the C result handle alive until the lazy NodeSet
materializes — and virtually every consumer materializes anyway
(each/size/to_a). Materialize eagerly in C instead: one face runs
the bulk pass AND frees the result handle, returning the Ruby
Array; Searchable wraps it in the eager NodeSet constructor (an
Array-backed set has no handle at all). Exotic node kinds (the
module-object sentinel) fall back to the existing lazy path with
the handle intact.

Gates: xpath results identical for every kind (including
sentinel-graded kinds); laziness is internal — the public NodeSet
behaviors (indexing, iteration, size) unchanged; the xpath row
drops the AutoPointer cost per call.

## Outcome (1.9.174.4)

Native.materialize_xpath: the bulk pass AND the result free in C;
Searchable's nodeset branch wraps the returned Array in the eager
NodeSet (no AutoPointer, no Method object, no finalizer per
xpath call). Sentinel scans happen in C (a Ruby include? would
cost microseconds on large sets) — any exotic kind returns Qnil
with the handle alive for the lazy fallback. Measured (load
~11): full materialization of a 2000-node xpath set 55.9µs vs
Nokogiri 57.3µs — parity on the heavy shape.
