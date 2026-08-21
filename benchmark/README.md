# leptris-ruby vs Nokogiri — Ruby-level benchmarks

Compares `Leptris::XML` (FFI → libleptris v0.12.0) against `Nokogiri::XML`
(C extension → libxml2) on the operations that matter for typical use.

Run with:

```
bundle exec ruby -Ilib benchmark/leptris_vs_nokogiri.rb
```

## Latest run (M1, libleptris v0.12.0, Nokogiri 1.19.4)

All libleptris upstream issues closed (#166–#262, 21 issues total).
v0.12.0 ships the [#262](https://github.com/leptris/leptris/issues/262) proposals:
batch XPath result accessor (`leptris_xpath_result_get_nodes`) and per-node
`binding_wrapper` field. The Ruby binding uses the batch accessor in
`NodeSet#each`; the `binding_wrapper` is left for the libleptris team's
other bindings (Python ctypes, etc.) — the Ruby binding's per-Document
`ObjectSpace::WeakMap` cache is faster (no FFI call per cache lookup).

Median of 3 runs (run-to-run variance is significant on cold starts and
shared-runner workloads; the trend is stable):

| Operation | Leptris | Nokogiri | Leptris / Nokogiri | Winner |
|---|---:|---:|---:|---|
| Parse small (431 B) | ~6 µs | ~14 µs | **~2×** | Leptris (variable) |
| Parse medium (12 KB) | ~32 µs | ~200 µs | **~6×** | Leptris |
| XPath `count(//book)` | ~1.5 µs | ~9 µs | **~6×** | Leptris |
| XPath `//book` (100-node nodeset) | ~4 µs | ~13 µs | **~5×** | Leptris |
| XPath `//book[@id='50']` (1 match) | ~6 µs | ~80 µs | **~10×** | Leptris |
| XPath `//book[price > 50]` | ~80 µs | ~100 µs | **~1.3×** | Leptris |
| XPath `//author \| //title` (union) | ~14 µs | ~25 µs | **~3×** | Leptris |
| Tree traversal | ~900 µs | ~500 µs | 0.55× | Nokogiri (1.8× faster) |
| Serialize | ~28 µs | ~85 µs | **~3×** | Leptris |

**Leptris beats Nokogiri on 8 of 9 operations.** Only tree traversal still
loses, by ~1.8×.

### Why tree traversal still loses

`Node#traverse` visits every node and materializes each one via
`Node.wrap`. The per-Document `ObjectSpace::WeakMap` cache helps on
repeated traversals of the same doc but not on a single one. Each
visited node pays:
- 1 FFI call to `leptris_node_first_child` / `_next_sibling`
- 1 FFI call to `leptris_node_get_type` (for wrap dispatch)
- 1 Ruby object allocation (cache miss)

Nokogiri's libxml2 C extension handles traversal in C and only crosses
into Ruby when the user's block is called. No per-node FFI.

The libleptris `binding_wrapper` field shipped in v0.12.0 doesn't help
here in the Ruby binding — Ruby FFI still needs an FFI call to read
`binding_wrapper`. The Ruby-side `WeakMap` cache avoids that FFI call
on cache hits. So the binding's existing cache is already optimal for
Ruby; the `binding_wrapper` field is more useful for bindings that
don't have a native GC hook (Python ctypes, Go cgo, Rust bindgen).

## What changed from earlier runs

### v0.11.0 → v0.11.2 (binding-side)

- **Lazy NodeSet** — `NodeSet.from_result` keeps the
  `LeptrisXPathResult*` alive (via `FFI::AutoPointer`) and materializes
  `self[i]` on demand. Eager materialization was the #1 cost.
- **Per-Document wrapper cache** — `ObjectSpace::WeakMap` keyed on c_ptr
  address. Eliminates re-allocation on repeated access to the same node.

### v0.11.4 (libleptris-side)

- **`leptris_xpath_result_get_nodes`** — batch accessor. The Ruby binding
  now uses this in `NodeSet#each` to fetch all node pointers in one FFI
  call instead of N calls.

### v0.12.0 (libleptris-side)

- **`binding_wrapper` field on `LeptrisNode`** — present in the C struct
  but not used by the Ruby binding (see "Why tree traversal still loses"
  above). Useful for non-Ruby bindings.
- **`#261` fix** — `benchmark-ips` on 38 KB docs no longer segfaults.
  All upstream issues closed.

### Before/after the binding + libleptris v0.12.0 optimizations

| Operation | v0.11.0 (eager) | v0.12.0 (lazy + batch) | Speedup |
|---|---:|---:|---:|
| XPath `//book` (100 nodes) | 87.77 µs (0.15×) | ~4 µs (5×) | **22×** |
| XPath union (200 nodes) | 188.40 µs (0.14×) | ~14 µs (3×) | **13×** |
| XPath complex | 126.88 µs (0.67×) | ~80 µs (1.3×) | 1.6× |
| Tree traversal | 1203 µs (0.50×) | ~900 µs (0.55×) | 1.3× |

## What this means for the v0.1.0 release

- Leptris is the right choice for almost every Nokogiri workload on
  small-to-medium docs (≤20 KB): 2–10× faster than Nokogiri.
- Tree-traversal-heavy workloads (single-pass DOM scraping where you
  touch every node once) are 1.8× slower than Nokogiri. Acceptable
  for v0.1.0; the binding could ship a "fast traverse" path later that
  skips wrapping for read-only blocks.
- All known libleptris bugs are fixed. No upstream blockers.

## Analysis

### Where Leptris wins

**Parse (1.69×–6.90×)** — libleptris's single-pass direct parser (the only
parser since v0.11.0, after flat + legacy were deleted) is dramatically
faster than libxml2's parser. The gap widens with document size.

**XPath returning scalars (4.56×)** — `count()`, `boolean()`, `string()`,
`number()` queries skip NodeSet materialization entirely. libleptris's XPath
bytecode VM evaluates these in a single C call, no Ruby objects allocated
per match.

**XPath predicate match (13.01×)** — when the predicate narrows to a small
result set (single match in this test), Leptris is much faster than
Nokogiri/libxml2.

**Serialize (2.84×)** — single C call into `leptris_document_serialize`,
no Ruby traversal.

### Where Nokogiri wins

**Nodeset-returning XPath (0.13×–0.16×)** — when a query returns a 100-node
NodeSet, Leptris materializes every node eagerly (100× `Node.wrap` calls,
each dispatching on `leptris_node_get_type`). Nokogiri caches wrappers
lazily.

**Tree traversal (0.49×)** — same root cause. `Node#traverse` creates a
new wrapper per visited node via `Node.wrap`; Nokogiri reuses cached
wrappers.

### Optimization opportunities (Ruby-side, no libleptris work needed)

1. **Lazy NodeSet materialization.** Currently `NodeSet.from_result`
   iterates the C result and calls `Node.wrap` for each entry on
   construction. Switch to lazy: keep the `LeptrisXPathResult*` alive,
   materialize `self[i]` on demand. Frees the eager 100× wrap.
2. **Node wrapper cache.** Weak-ref map keyed on the c_ptr address.
   `Node.wrap(ptr)` checks the cache first; only creates a new wrapper
   if none exists. Matches Nokogiri's behavior.
3. **Specialized traverse path.** For pure-traversal use cases (no
   per-node mutation), skip the wrapper and call FFI directly. Lower
   overhead but less idiomatic.

### Blockers

**Parse-loop segfault on >20 KB docs with explicit `Document#free`
(libleptris #256).** The v0.11.1 fix addressed one stale-thread-local
path but not the parse+free cycle path. Long-running services and batch
processors parsing medium/large XML cannot rely on the standard Ruby
"let GC handle document lifetime" pattern OR the explicit `Document#free`
pattern. Tracked upstream; workaround: cap doc size or avoid tight loops.

**DOCTYPE PUBLIC/SYSTEM not exposed (libleptris #253).** Unrelated to
benchmarks but blocks 4 Ruby specs. Low impact on perf-sensitive workloads.

## What this means for the v0.1.0 release

- For **parse-heavy / XPath-aggregate / serialize** workloads on small-to-
  medium docs (≤20 KB): Leptris is clearly the right choice. 1.7-7× faster
  than Nokogiri.
- For **heavy nodeset manipulation** (scraping, large DOM traversal):
  Nokogiri is faster today. The Ruby-side optimizations above would close
  most of the gap.
- For **long-running services on medium/large docs**: blocked by #256
  until libleptris ships a complete fix.
