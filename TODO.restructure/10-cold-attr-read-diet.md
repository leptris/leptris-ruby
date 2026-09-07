# 10 — Cold attribute reads: value-only materialization (#150)

Status: DONE

`Element#[]`'s cold path called `attributes` — building Attr
wrappers, the name-keyed Attr hash, and the values hash (~17
allocations for a 2-attribute element) to answer ONE bare-name
read.

## Change

- [x] `Element#materialize_attr_values`: walks the v1.1.0
      attribute linked-list face filling ONLY the versioned
      `@attr_values` memo — no Attr wrappers, no side hashes.
      `[]`'s cold branch uses it; `attributes`/`attribute_nodes`/
      `keys`/`values` keep their richer materialization (they
      answer richer questions).
- [x] Alloc-count spec: cold `[]` on a 2-attribute element stays
      under a fixed budget (was ~17 allocs).
