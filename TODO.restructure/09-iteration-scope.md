# 09 — IterationScope: lifetime + memoization for iterparse elements (#152)

Status: DONE

Root cause of both #152 findings: `Iterparse#run` wraps yielded
elements with `document: nil` — so (a) `ensure_alive!` has nothing
to check (post-free use segfaults instead of raising), and (b)
every memoized read (`[]`, `attribute_nodes`, …) skips the memo
machinery entirely (the 10-30x parentless cost: `attribute_nodes`
re-walks per call, `[]` pays the raw path).

## Change

- [x] New `Leptris::XML::IterationScope` (autoloaded): the owning
      context for yielded elements — carries the iterator handle
      as its lifetime anchor (`#c_ptr` goes nil on `#free`, the
      same signal `ensure_alive!` reads), a `wrapper_cache`
      (identity for a subtree's wrappers), and a `version` that
      advances per yield (stale memos on held wrappers invalidate
      as subtrees are released).
- [x] `Node#document` answers nil for scope-owned elements — the
      documented contract ("#document returns nil") is preserved
      while the internal machinery engages.
- [x] `Iterparse#free` frees the scope; the block form's ensure
      chain rides it.
- [x] Specs: post-iteration use of a held element raises
      `UseAfterFreeError` (was: VM segfault); repeated
      `attribute_nodes` inside the block memoizes; children
      identity holds within a yielded subtree.
