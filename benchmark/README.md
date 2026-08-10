# taurus-ruby vs Nokogiri — Ruby-level benchmarks

Compares `Taurus::XML` (FFI → libtaurus v0.11.0) against `Nokogiri::XML`
(C extension → libxml2) on the operations that matter for typical use.

Run with:

```
bundle exec ruby -Ilib benchmark/taurus_vs_nokogiri.rb
```

## Latest run (M1, libtaurus v0.11.0, Nokogiri 1.19.4)

| Operation | Taurus | Nokogiri | Taurus / Nokogiri | Winner |
|---|---:|---:|---:|---|
| Parse small (431 B) | 5.49 µs | 10.95 µs | **1.99×** | Taurus |
| Parse medium (12 KB) | 27.21 µs | 177.04 µs | **6.51×** | Taurus |
| XPath `count(//book)` | 1.53 µs | 8.32 µs | **5.45×** | Taurus |
| XPath `//book` (100-node nodeset) | 64.16 µs | 9.00 µs | 0.14× | Nokogiri (7× faster) |
| XPath `//book[@id='50']` (1 match) | 4.12 µs | 51.05 µs | **12.39×** | Taurus |
| XPath `//book[price > 50]` | 93.83 µs | 67.52 µs | 0.72× | Nokogiri (slight) |
| XPath `//author \| //title` (union) | 133.09 µs | 21.10 µs | 0.16× | Nokogiri (6× faster) |
| Tree traversal | 885.34 µs | 423.87 µs | 0.48× | Nokogiri (2× faster) |
| Serialize | 27.40 µs | 79.45 µs | **2.90×** | Taurus |

## Analysis

### Where Taurus wins

**Parse (1.99×–6.51×)** — libtaurus's single-pass direct parser (the only
parser since v0.11.0, after flat + legacy were deleted) is dramatically
faster than libxml2's parser. The gap widens with document size.

**XPath returning scalars (5.45×)** — `count()`, `boolean()`, `string()`,
`number()` queries skip NodeSet materialization entirely. libtaurus's XPath
bytecode VM evaluates these in a single C call, no Ruby objects allocated
per match.

**XPath predicate match (12.39×)** — when the predicate narrows to a small
result set (single match in this test), Taurus is much faster than
Nokogiri/libxml2.

**Serialize (2.90×)** — single C call into `taurus_document_serialize`,
no Ruby traversal.

### Where Nokogiri wins

**Nodeset-returning XPath (0.14×–0.16×)** — when a query returns a 100-node
NodeSet, Taurus materializes every node eagerly (100× `Node.wrap` calls,
each dispatching on `taurus_node_get_type`). Nokogiri caches wrappers
lazily.

**Tree traversal (0.48×)** — same root cause. `Node#traverse` creates a
new wrapper per visited node via `Node.wrap`; Nokogiri reuses cached
wrappers.

### Optimization opportunities (Ruby-side, no libtaurus work needed)

1. **Lazy NodeSet materialization.** Currently `NodeSet.from_result`
   iterates the C result and calls `Node.wrap` for each entry on
   construction. Switch to lazy: keep the `TaurusXPathResult*` alive,
   materialize `self[i]` on demand. Frees the eager 100× wrap.
2. **Node wrapper cache.** Weak-ref map keyed on the c_ptr address.
   `Node.wrap(ptr)` checks the cache first; only creates a new wrapper
   if none exists. Matches Nokogiri's behavior.
3. **Specialized traverse path.** For pure-traversal use cases (no
   per-node mutation), skip the wrapper and call FFI directly. Lower
   overhead but less idiomatic.

### Blockers

**Parse-loop segfault on >20 KB docs (libtaurus #256).** Long-running
services and batch processors parsing medium/large XML cannot rely on
the standard Ruby "let GC handle document lifetime" pattern. Workaround
is explicit `Document#free`. Tracked upstream.

## What this means for the v0.1.0 release

- For **parse-heavy / XPath-aggregate / serialize** workloads: Taurus is
  clearly the right choice. 2-6× faster than Nokogiri.
- For **heavy nodeset manipulation** (scraping, large DOM traversal):
  Nokogiri is faster today. The Ruby-side optimizations above would
  close most of the gap.
- The segfault (#256) is the only hard blocker for general use.
