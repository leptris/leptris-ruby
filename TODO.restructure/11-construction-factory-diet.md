# 11 — Programmatic construction: wrap-fresh factories (#149)

Status: DONE (binding-side diet; structural ceiling documented)

- [x] `Node.wrap_fresh`: one construction authority shared with
      `wrap` (the type dispatch is not duplicated), skipping the
      cache LOOKUP only — a freshly created pointer cannot be in
      the cache, so the lookup was a guaranteed miss on every
      factory call. Cache STORE still happens (identity survives
      attach).
- [x] `Document.create_element/create_text_node/create_comment/
      create_cdata` route through it.
- [x] Measured before/after on the issue's bench shape; the
      remaining gap is per-call FFI marshaling vs a C extension —
      the structural ceiling of the FFI-only architecture,
      documented on the issue.
