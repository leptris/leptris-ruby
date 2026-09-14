# 21 — #147 option B: TypedData wrapper variant (owner greenlit)

Status: round 2 PASSED (2026-09-14) — branch proto/native-nodes
is the reference implementation; build phase remains (full read
surface, seam, 9-platform packaging). Round 1 handle-level spike
(feat/typed-wrapper-variant, never merged) FAILED its gate — held
-8% vs walks +40% because per-call FFI::Pointer marshaling
dominates; the fix was C-binding the reads themselves.

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

## Round 2 (2026-09-14): converged native nodes — PASSED

ext/leptris/native/native.c: TypedData wrappers (ptr + document
embedded), C-bound hot reads via dlsym (no FFI marshaling), bulk
children (one cache round-trip, zero Ruby frames). Measured: walk
17.2 -> 2.8 ms (6.2x, interleaved best-of under load ~148 — ratio
conservative); held wrappers ~54 kB/doc (RSS, load-independent).
Identity shared through the binding wrapper_cache. Data on #185.
Remaining: full read surface, variant seam, compiled-ext
packaging (9-platform), release.
