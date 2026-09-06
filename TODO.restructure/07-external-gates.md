# 07 — External gates (blocked outside this repo; tracked, not completable here)

Status: TRACKED

- [ ] **leptris/leptris#875 re-adoption**: when the fix releases,
      re-pin to `{C}`, un-pend the sentinel spec, re-run the
      96/97/120 boundary + the 120-template perf fixture as the
      release gate, ship `{C}.0`. (1.9.93.0/1.9.93.1 yanked;
      1.9.92.1 is the standing replacement.)
- [ ] **utf8proc build decision** (owner): `fn:normalize-unicode`
      requires utf8proc, compiled out of the vendored platform
      builds — enabling it changes the vendored binary surface.
      Pending spec documents it.
- [ ] **#147 option A/B/C** (owner): A (document — DONE via 05),
      B (FFI+native `leptris-typed` variant gem — roadmap), C
      (revisit if ruby-ffi grows TypedData).
- [ ] **#683 remainder** (upstream): 3.1 string templates, XQuery
      3.1 territory.
