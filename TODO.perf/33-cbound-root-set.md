# 33 — C-bound root=

Status: DONE (1.9.174.8)

The last mutation on the FFI path: Document#root= runs the lift
guard, FFI leptris_document_set_root, wrap-seeding, and version
bookkeeping — and the post-round-8 build profile shows its FFI
call plus the lazy-c_ptr materialization feeding it (~2.4% of a
fresh-doc build each). One face runs gates + bump + engine
set_root and returns the wrapped+memo-seeded root (the wrap
seed keeps identity across the copy_of/fast paths that read
@root immediately).

Gates: root= semantics unchanged (liftoff guard with the
skip fast path, cross-doc invalidation, @root seeding through
wrap for correct document association); readonly raises; the
build row improves by the marshaling share.

## Outcome (1.9.174.8)

Native.set_binding_root wired into Document#root= (gates + bump
+ engine set_root in one dispatch; the wrap seed and
cross-document invalidation stay in Ruby). The face exposed a
real divergence: the FFI path never gated readonly for root= —
silently mutating frozen documents — while the face raises
ReadOnlyError per the binding's contract. The FFI path now gates
too (one ivar read; readonly is one-way), with a both-modes
spec. Cross-document root= raises identically on both paths
(pre-existing engine rejection).
