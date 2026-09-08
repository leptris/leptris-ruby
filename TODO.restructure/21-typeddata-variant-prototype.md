# 21 — #147 option B: TypedData wrapper variant (owner greenlit)

Status: QUEUED (dedicated round)

The greenlight arrived ("proceed with all"); the execution plan,
in verification order:

- [ ] Minimal C ext (one file): a TypedData class holding
      (pointer, document-ref) with the Node duck surface the hot
      paths need — installed as a compiled gem.
- [ ] Measure the hypothesis first: held-RSS of a walked tree with
      TypedData wrappers vs FFI::Pointer wrappers (predicted
      ~28% of the wrapper layer, ~552 kB/doc → ~400 kB/doc).
- [ ] If validated: design the `Node.construct` factory seam to
      select wrapper classes per variant (OCP — one seam, no
      scatter), then the variant gem + platform matrix.
- [ ] If NOT validated (win < ~15%): record the negative result on
      #147 and close option B with data.
