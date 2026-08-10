# taurus-ruby vs Nokogiri — Ruby-level benchmarks

Compares `Taurus::XML` (FFI → libtaurus v0.11.2) against `Nokogiri::XML`
(C extension → libxml2) on the operations that matter for typical use.

Run with:

```
bundle exec ruby -Ilib benchmark/taurus_vs_nokogiri.rb
```

## Latest run (M1, libtaurus v0.11.2, Nokogiri 1.19.4)

| Operation | Taurus | Nokogiri | Taurus / Nokogiri | Winner |
|---|---:|---:|---:|---|
| Parse small (431 B) | 9.02 µs | 15.12 µs | **1.68×** | Taurus |
| Parse medium (12 KB) | 31.93 µs | 226.31 µs | **7.09×** | Taurus |
| XPath `count(//book)` | 2.04 µs | 11.48 µs | **5.63×** | Taurus |
| XPath `//book` (100-node nodeset) | 87.77 µs | 13.07 µs | 0.15× | Nokogiri (6.9× faster) |
| XPath `//book[@id='50']` (1 match) | 4.73 µs | 66.37 µs | **14.03×** | Taurus |
| XPath `//book[price > 50]` | 126.88 µs | 85.26 µs | 0.67× | Nokogiri (slight) |
| XPath `//author \| //title` (union) | 188.40 µs | 27.24 µs | 0.14× | Nokogiri (6.9× faster) |
| Tree traversal | 1203.44 µs | 606.17 µs | 0.50× | Nokogiri (2× faster) |
| Serialize | 33.73 µs | 99.20 µs | **2.94×** | Taurus |

### v0.11.0 → v0.11.2 binding-level delta

Two changes between v0.11.0 and the current run:

1. **libtaurus v0.11.2** — fixed #253 (DOCTYPE PUBLIC/SYSTEM) and made a
   partial fix to #256 (converted `taurus_node_freeze` from recursive to
   iterative with a fixed 256-deep explicit stack).
2. **Ruby binding lifetime refactor** — replaced `FFI::AutoPointer` (which
   double-freed on the explicit `Document#free` + later-GC path) with a
   manual `ObjectSpace.define_finalizer` pattern using a shared `Freed`
   flag container. This was the actual root cause of most parse-loop
   crashes attributed to libtaurus #256 in earlier runs.

Combined: explicit `parse + free` loops and GC-pressure loops on 38 KB
docs now work cleanly (5000+ iterations verified). `benchmark-ips` on
38 KB docs still crashes inside `taurus_node_freeze+0x150`; maintainer's
C reproducer (5000 iter, 200 docs alive, ASAN) passes, mine doesn't.
Repro and analysis in [#256 comment](https://github.com/lutaml/taurus/issues/256#issuecomment-5235291258).

The slight numeric regression vs v0.11.0 (parse small 5.49 → 9.02 µs,
serialize 27.40 → 33.73 µs) is the cost of the explicit finalizer
pattern — `ObjectSpace.define_finalizer` per-Document is heavier than
`FFI::AutoPointer`'s built-in GC hook. Worth it for correctness.

## Analysis

### Where Taurus wins

**Parse (1.68×–7.09×)** — libtaurus's single-pass direct parser (the only
parser since v0.11.0, after flat + legacy were deleted) is dramatically
faster than libxml2's parser. The gap widens with document size.

**XPath returning scalars (5.63×)** — `count()`, `boolean()`, `string()`,
`number()` queries skip NodeSet materialization entirely. libtaurus's XPath
bytecode VM evaluates these in a single C call, no Ruby objects allocated
per match.

**XPath predicate match (14.03×)** — when the predicate narrows to a small
result set (single match in this test), Taurus is much faster than
Nokogiri/libxml2.

**Serialize (2.94×)** — single C call into `taurus_document_serialize`,
no Ruby traversal.

### Where Nokogiri wins

**Nodeset-returning XPath (0.14×–0.15×)** — when a query returns a 100-node
NodeSet, Taurus materializes every node eagerly (100× `Node.wrap` calls,
each dispatching on `taurus_node_get_type`). Nokogiri caches wrappers
lazily.

**Tree traversal (0.50×)** — same root cause. `Node#traverse` creates a
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

**`benchmark-ips` segfault on 38 KB docs (libtaurus #256, partially
fixed in v0.11.2).** The libtaurus-side iterative-freeze fix + the
Ruby-side AutoPointer fix together resolve the parse+free and
GC-pressure patterns. Only `benchmark-ips` (which accumulates return
values differently) still segfaults inside `taurus_node_freeze+0x150`.
Likely a residual libtaurus issue or a different finalizer-timing bug
in the Ruby binding. Tracked in #256.

**DOCTYPE `internal_subset` still returns nil (libtaurus #253,
partially fixed in v0.11.2).** PUBLIC/SYSTEM identifiers are now
exposed correctly. The internal subset is parsed by libtaurus (per
v0.9.0 release notes — used for entity expansion) but not surfaced via
`taurus_doctype_get_internal_subset`. 1 Ruby spec still pending.

## What this means for the v0.1.0 release

- For **parse-heavy / XPath-aggregate / serialize** workloads on small-to-
  medium docs (≤20 KB): Taurus is clearly the right choice. 1.7-7× faster
  than Nokogiri.
- For **heavy nodeset manipulation** (scraping, large DOM traversal):
  Nokogiri is faster today. The Ruby-side optimizations above would close
  most of the gap.
- For **long-running services with high parse churn**: safe under typical
  Ruby lifetime patterns (explicit `free`, or GC). Not safe under
  `benchmark-ips`-style accumulation — niche but worth tracking.

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
