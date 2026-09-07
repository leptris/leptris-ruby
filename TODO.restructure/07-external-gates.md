# 07 — External gates (blocked outside this repo; tracked, not completable here)

Status: TRACKED

- [x] **leptris/leptris#875 re-adoption** — DONE in 1.9.100.0
      (fix landed upstream in 1.9.97; sentinel gate extended to
      500/500; perf reclaimed).
- [ ] **utf8proc build decision** (owner): `fn:normalize-unicode`
      requires utf8proc, compiled out of the vendored platform
      builds — enabling it changes the vendored binary surface.
      Pending spec documents it.
- [ ] **#147 option A/B/C** (owner): A (document — DONE via 05),
      B (FFI+native `leptris-typed` variant gem — roadmap), C
      (revisit if ruby-ffi grows TypedData).
- [ ] **#683 remainder** (upstream): 3.1 string templates, XQuery
      3.1 territory.
