# taurus-ruby vs Nokogiri — Ruby-level benchmarks

Compares `Taurus::XML` (FFI → libtaurus v0.11.1) against `Nokogiri::XML`
(C extension → libxml2) on the operations that matter for typical use.

Run with:

```
bundle exec ruby -Ilib benchmark/taurus_vs_nokogiri.rb
```

## Latest run (M1, libtaurus v0.11.1, Nokogiri 1.19.4)

| Operation | Taurus | Nokogiri | Taurus / Nokogiri | Winner |
|---|---:|---:|---:|---|
| Parse small (431 B) | 7.09 µs | 12.01 µs | **1.69×** | Taurus |
| Parse medium (12 KB) | 26.83 µs | 185.04 µs | **6.90×** | Taurus |
| XPath `count(//book)` | 1.91 µs | 8.69 µs | **4.56×** | Taurus |
| XPath `//book` (100-node nodeset) | 70.67 µs | 9.11 µs | 0.13× | Nokogiri (7.7× faster) |
| XPath `//book[@id='50']` (1 match) | 4.21 µs | 54.80 µs | **13.01×** | Taurus |
| XPath `//book[price > 50]` | 99.96 µs | 70.13 µs | 0.70× | Nokogiri (slight) |
| XPath `//author \| //title` (union) | 143.06 µs | 22.40 µs | 0.16× | Nokogiri (6.4× faster) |
| Tree traversal | 917.82 µs | 449.87 µs | 0.49× | Nokogiri (2.0× faster) |
| Serialize | 27.93 µs | 79.41 µs | **2.84×** | Taurus |

### v0.11.0 → v0.11.1 delta

The v0.11.1 release fixes one stale-thread-local in the parse path
(upstream #256 partial fix). Run-to-run variance dominates any
real algorithmic change — perf is unchanged within measurement noise.
The #256 fix is **incomplete**: parse + explicit `Document#free` cycles
on ~38 KB docs still segfault. See [issue #256 comment](https://github.com/lutaml/taurus/issues/256#issuecomment-5235291258).

## Analysis

### Where Taurus wins

**Parse (1.69×–6.90×)** — libtaurus's single-pass direct parser (the only
parser since v0.11.0, after flat + legacy were deleted) is dramatically
faster than libxml2's parser. The gap widens with document size.

**XPath returning scalars (4.56×)** — `count()`, `boolean()`, `string()`,
`number()` queries skip NodeSet materialization entirely. libtaurus's XPath
bytecode VM evaluates these in a single C call, no Ruby objects allocated
per match.

**XPath predicate match (13.01×)** — when the predicate narrows to a small
result set (single match in this test), Taurus is much faster than
Nokogiri/libxml2.

**Serialize (2.84×)** — single C call into `taurus_document_serialize`,
no Ruby traversal.

### Where Nokogiri wins

**Nodeset-returning XPath (0.13×–0.16×)** — when a query returns a 100-node
NodeSet, Taurus materializes every node eagerly (100× `Node.wrap` calls,
each dispatching on `taurus_node_get_type`). Nokogiri caches wrappers
lazily.

**Tree traversal (0.49×)** — same root cause. `Node#traverse` creates a
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

**Parse-loop segfault on >20 KB docs with explicit `Document#free`
(libtaurus #256).** The v0.11.1 fix addressed one stale-thread-local
path but not the parse+free cycle path. Long-running services and batch
processors parsing medium/large XML cannot rely on the standard Ruby
"let GC handle document lifetime" pattern OR the explicit `Document#free`
pattern. Tracked upstream; workaround: cap doc size or avoid tight loops.

**DOCTYPE PUBLIC/SYSTEM not exposed (libtaurus #253).** Unrelated to
benchmarks but blocks 4 Ruby specs. Low impact on perf-sensitive workloads.

## What this means for the v0.1.0 release

- For **parse-heavy / XPath-aggregate / serialize** workloads on small-to-
  medium docs (≤20 KB): Taurus is clearly the right choice. 1.7-7× faster
  than Nokogiri.
- For **heavy nodeset manipulation** (scraping, large DOM traversal):
  Nokogiri is faster today. The Ruby-side optimizations above would close
  most of the gap.
- For **long-running services on medium/large docs**: blocked by #256
  until libtaurus ships a complete fix.
