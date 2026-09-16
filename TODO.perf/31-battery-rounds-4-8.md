# 31 — Battery rows for the round 4-8 surfaces

Status: DONE (1.9.174.8)

The drift battery (benchmark/native_vs_binding.rb) predates
TODO.perf/22-30: eager materialization, C-yield traversal,
streaming bulk, one-dispatch dup, ns-xpath on the compiled path,
first/last element-child walks, and the value mutations have no
rows — nothing regression-gates them. Add interleaved best-of
rows behind the file's load gate for each, mirroring the shapes
measured in their TODO docs.

Gates: every row runs under load <20 (the file's own gate) and
prints both surfaces where two exist (FFI vs native via
LEPTRIS_NO_NATIVE).

## Outcome (1.9.174.8)

Seven new rows behind the file's load gate: iterparse walk 4k,
traverse/visit over the 14k-node doc, ns-bearing element dup,
xpath union materialization, first+last element child, and the
name=+content= pair. The round-4-8 surfaces are now
regression-gated.
