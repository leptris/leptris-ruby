# 21 — #147 option B: TypedData wrapper variant (owner greenlit)

Status: GATE FAILED at the handle level (2026-09-13, in-repo
round 1) — artifact preserved on branch feat/typed-wrapper-variant

Round 1 (in-repo, libleptris 1.9.152 / Ruby 3.4.8): the full
584-example suite passes with TypedPtr handles (LEPTRIS_WRAPPER=typed,
single handle_for seam in Node.wrap/wrap_fresh, ext/
leptris/typed_ptr/typed_ptr.c). But the binding-level measurement
kills the handle-level shape:

- held docs: 4511 -> 4304 kB/doc (~8% — the projected 48 B/node
  saving survives only partially in RSS; FFI::Pointer cost was
  88 B, TypedPtr is 40 B, fragmentation eats the rest)
- walks: 16.2 -> 22.7 ms/doc (+40%) — per-call to_ptr marshaling
  allocates a transient 88 B FFI::Pointer per FFI call
  (+21.5k allocs/doc)
- cached-pointer variant would invert both: held 40+88=128 B/node
  (WORSE than the 88 B status quo), walks fast.

The 114 B/node prototype number came from standalone holders with
no FFI activity; in the real binding every node read marshals
through FFI, forcing the pointer back into existence. Conclusion:
TypedData cannot pay for itself while reads go through FFI
marshaling. A viable option B' would move the hot node reads
(children/name/content/type) INTO the C ext — a genuine partial
C-binding fork of the wrapper layer, only worth building if
held-doc memory becomes a sustained user complaint. Original
prototype notes (standalone validation) follow.

The greenlight arrived ("proceed with all"); the execution plan,
in verification order:

- [x] Minimal C ext (one file): a TypedData class holding
      (pointer, document-ref) — prototype built and measured
      (ext + bench preserved under /tmp/typedproto, /tmp/bench_typed.rb).
- [x] NOTE (2026-09-12): /tmp was wiped — the prototype ext and
      bench under /tmp/typedproto, /tmp/bench_typed.rb are GONE.
      The measurements below stand (recorded here); the build
      phase rebuilds the ext properly under ext/ anyway.
- [x] Measured (100k holders, GC.settled RSS deltas):
      FFI::Pointer-backed 154 B/node vs TypedData 40 B/node —
      **114 B/node saved**, ~40% of the wrapper layer (#147's
      +552 kB/doc → ~+330 kB/doc, held 1.57x → ~1.2x Nokogiri).
      The mark-function document ref works (no GC-safety loss).
- [ ] VALIDATED — build phase: the `Node.construct` factory seam
      selects wrapper classes per variant (OCP — one seam, no
      scatter), then the variant gem + 9-platform matrix with the
      compiled ext. Multi-round build (new gemspec, ext
      compilation per platform, packaging).
- [ ] If NOT validated (win < ~15%): record the negative result on
      #147 and close option B with data.
