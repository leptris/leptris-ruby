# 12 — Document lifetime in C: TypedData handle replaces the ObjectSpace finalizer

Status: DONE (1.9.163.6)

Every document (parsed AND created) registers an ObjectSpace
finalizer: a per-document proc allocation (~110ns), the
define_finalizer call (~315ns), the Freed struct, and — the real
cost — a Ruby finalizer invocation at GC time that must dispatch
back through FFI to leptris_document_free (~1-2µs per document
inside GC pauses). Fresh-document build loops measured 7.1µs per
Document.create in-loop, ~4-5µs of it GC/finalizer amortization
(stackprof: GC ~19% of a build loop, define_finalizer+proc in the
top frames).

Fix: a TypedData DocHandle (struct { void *doc; }) whose dfree
calls leptris_document_free directly — no Ruby finalizer, no FFI
from finalizer context, no proc. The handle is referenced only by
the Document's @doc_handle ivar, so its lifetime IS the
Document's. Document#free keeps its explicit path (FFI free +
release the handle's pointer so dfree no-ops — the same
double-free protocol Freed enforces today, in C). The proc
finalizer stays for LEPTRIS_NO_NATIVE mode.

Companion: Native.create_binding_document — the full
Document.create in one C dispatch (engine create + wrapper
allocation + @c_ptr/@c_address/@freed/@readonly/@version + handle
attach). Document.create today pays FFI marshaling + wrap frames
(~250-600ns) on top of the engine call.

Gates: lifetime_contract_spec + memory_spec green in both modes;
double-free impossible (free → dfire no-op, finalizer-mode
unchanged); Document.create and fresh-doc build rows improve.

## Outcome (1.9.163.6)

DocHandle TypedData (struct { void *doc; }, RUBY_TYPED_FREE_IMMEDIATELY,
dfree -> leptris_document_free) attached as @doc_handle on every
wrap() when native is enabled; Document#free detaches it (dfree
no-ops). Native.create_binding_document does engine create +
ivar-seeded wrapper + handle in one dispatch (Document.create
routes through it). Freed stays the shared free-state; the proc
finalizer remains for LEPTRIS_NO_NATIVE. 3,000-doc GC-reclamation
and explicit-free-then-GC specs green; 647/0 both modes. Measured
under host load 14-30: GC-amortized Document.create ~5.0us (the
Ruby-finalizer invocation and FFI-dispatch-at-GC are gone from
every document lifecycle; clean-load numbers pending the battery
— the box never dropped under load 13 this session).
