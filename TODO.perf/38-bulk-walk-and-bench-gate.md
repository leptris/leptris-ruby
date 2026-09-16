# 38 — Bulk hydration + bench gate + Document.open

Status: DONE (1.9.178.1)

## Outcome

- **#229**: `benchmark/native_vs_binding.rb` now accepts
  `LEPTRIS_BENCH_LOAD_MAX`; default threshold is core-normalized
  (`max(logical_cores * 1.5, 4.0)`) instead of absolute load >20.
- **#230**: `Document#snapshot(node)` returns C-materialized flat
  rows (`kind`, `name`, `prefix`, `uri`, flat `[name,value]` attrs,
  text, depth), and `Document#walk_subtree(node) { |row| ... }`
  yields the same rows. The native snapshot has no per-node Node
  wrappers or per-attribute Ruby calls. The cursor currently yields
  the safe snapshot rows; the direct Proc callback prototype was
  rejected after crashing MRI and is not shipped.
- **#231**: `Document.open(xml) { |doc| ... }` guarantees `doc.free`
  on normal and exceptional block exit. The strong identity cache
  remains the default deliberately: weak identity would break
  `doc.root.equal?(doc.root)` while the document remains alive.

Specs: 674/0 in both native and FFI modes. Downstream follow-ups
posted to moxml#230/#231 and metanorma/uniword#49.
