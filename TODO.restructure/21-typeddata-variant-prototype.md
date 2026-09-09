# 21 — #147 option B: TypedData wrapper variant (owner greenlit)

Status: PROTOTYPE DONE — hypothesis VALIDATED (114 B/node measured)

The greenlight arrived ("proceed with all"); the execution plan,
in verification order:

- [x] Minimal C ext (one file): a TypedData class holding
      (pointer, document-ref) — prototype built and measured
      (ext + bench preserved under /tmp/typedproto, /tmp/bench_typed.rb).
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
