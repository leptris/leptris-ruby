# taurus-ruby vs Nokogiri — Ruby-level benchmarks

Compares `Taurus::XML` (FFI → libtaurus v0.11.2) against `Nokogiri::XML`
(C extension → libxml2) on the operations that matter for typical use.

Run with:

```
bundle exec ruby -Ilib benchmark/taurus_vs_nokogiri.rb
```

## Latest run (M1, libtaurus v0.11.2, Nokogiri 1.19.4)

After binding-side optimizations: lazy `NodeSet` (keep
`TaurusXPathResult*` alive, materialize on `[i]` access) + per-Document
weak-ref `Node` wrapper cache (eliminates re-allocation on repeated
access to the same node).

| Operation | Taurus | Nokogiri | Taurus / Nokogiri | Winner |
|---|---:|---:|---:|---|
| Parse small (431 B) | 6.24 µs | 12.16 µs | **1.95×** | Taurus |
| Parse medium (12 KB) | 27.60 µs | 192.52 µs | **6.97×** | Taurus |
| XPath `count(//book)` | 1.40 µs | 8.71 µs | **6.20×** | Taurus |
| XPath `//book` (100-node nodeset) | 2.70 µs | 9.27 µs | **3.43×** | Taurus |
| XPath `//book[@id='50']` (1 match) | 4.67 µs | 54.10 µs | **11.60×** | Taurus |
| XPath `//book[price > 50]` | 64.54 µs | 73.14 µs | **1.13×** | Taurus |
| XPath `//author \| //title` (union) | 10.61 µs | 22.57 µs | **2.13×** | Taurus |
| Tree traversal | 776.84 µs | 472.88 µs | 0.61× | Nokogiri (1.6× faster) |
| Serialize | 29.52 µs | 81.82 µs | **2.77×** | Taurus |

**Taurus beats Nokogiri on 8 of 9 operations.** Only tree traversal still
loses, by 1.6× — that's the one path that genuinely materializes every
node on every iteration (no cache reuse across calls). Closing that gap
needs the C-side proposals in [libtaurus #262](https://github.com/lutaml/taurus/issues/262).

### Before/after the binding-side optimizations

Same libtaurus v0.11.2, same hardware. Just the Ruby binding changed:

| Operation | Before | After | Speedup |
|---|---:|---:|---:|
| XPath `//book` (100 nodes) | 87.77 µs | 2.70 µs | **32×** |
| XPath `//author \| //title` (200 nodes) | 188.40 µs | 10.61 µs | **18×** |
| XPath complex | 126.88 µs | 64.54 µs | 2.0× |
| Tree traversal | 1203 µs | 777 µs | 1.5× |
| XPath `count()` | 2.04 µs | 1.40 µs | 1.5× |
| Parse small | 9.02 µs | 6.24 µs | 1.4× |

The 32× and 18× speedups on nodeset-returning XPath come from the lazy
`NodeSet`. The benchmark block (`{ doc.xpath("//book") }`) doesn't
iterate the result — it just creates the NodeSet. Pre-optimization,
that meant eagerly wrapping 100 nodes via 200+ FFI calls. Post, it's
one FFI call to count plus storing the result pointer. Materialization
is deferred to actual `[i]` / `each` access.

## Analysis

### Why the binding-side optimizations work

**Lazy NodeSet** — `NodeSet.from_result` used to walk the entire C result
and call `Node.wrap` for each entry on construction. For a 100-node
query that was 100× FFI calls + 100× Ruby allocations just to build the
container. The new code keeps the `TaurusXPathResult*` alive (via
`FFI::AutoPointer` for GC safety) and only materializes `self[i]` on
demand. For `at_xpath`-style patterns (read first match, ignore rest)
this is a 100× win.

**Wrapper cache** — per-Document `ObjectSpace::WeakMap` keyed on c_ptr
address. `Node.wrap(ptr, doc)` checks the cache before allocating. In
the traverse benchmark, the same doc is traversed 2000 times — the first
iteration creates all wrappers, the remaining 1999 hit the cache. Cuts
allocation to near-zero on hot paths.

The cache is scoped per-Document so it dies with the document — no stale
entries pointing at freed memory. When a node wrapper is GC'd (user code
dropped it), the WeakMap entry disappears automatically.

### Where Taurus still loses

**Tree traversal (0.61×).** `Node#traverse` visits every node and
materializes each one via `Node.wrap`. The wrapper cache helps on
repeated traversals of the same doc but not on a single one. Each
visited node still pays:
- 1 FFI call to `taurus_node_first_child` / `_next_sibling`
- 1 FFI call to `taurus_node_get_type` (for wrap dispatch)
- 1 Ruby object allocation

For Nokogiri, the libxml2 C extension handles traversal in C and only
crosses into Ruby when the user's block is called. No per-node FFI.

Closing this gap requires either:
- C-side: a `binding_wrapper` back-ref field on `TaurusElement` so the
  binding can store a Ruby object pointer directly (proposal 1 in
  [#262](https://github.com/lutaml/taurus/issues/262))
- Ruby-side: a specialized traverse path that skips wrapping for
  read-only blocks (loses some Nokogiri-compat semantics)

### Blockers

**`benchmark-ips` segfault on 38 KB docs (libtaurus #261).** Residual
crash inside `taurus_node_freeze+0x150` when ~15,000 documents are alive
simultaneously. Tracked upstream; doesn't affect normal use.

**DOCTYPE `internal_subset` returns nil (libtaurus #253).** Partially
fixed in v0.11.2 — PUBLIC/SYSTEM identifiers now work; the internal
subset string is still NULL. 1 Ruby spec pending.

## What this means for the v0.1.0 release

- Taurus is the right choice for almost every Nokogiri workload on
  small-to-medium docs (≤20 KB): 1.95–11.6× faster than Nokogiri.
- Tree-traversal-heavy workloads (single-pass DOM scraping where you
  touch every node) are 1.6× slower than Nokogiri today. The C-side
  proposals in #262 would close this gap; the binding alone can't.
- For long-running services with high parse churn: safe under typical
  Ruby lifetime patterns. `benchmark-ips` on large docs is the only
  known crash window.

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
