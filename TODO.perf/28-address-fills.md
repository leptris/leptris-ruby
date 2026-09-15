# 28 — Address-based first-touch fills for the remaining reads

Status: DONE (1.9.174.6)

The memoized content readers still fill through FFI marshaling on
first touch — Text/Comment/CDATA/PI content, and Node#path
(owned-string read + free) — and the bulk attribute faces exclude
scope-owned elements though they touch no document state. Add the
trivial address faces (fast_text/comment/cdata content, pi
target/data, node path with the free protocol) and switch the
fills to @addr_reads_fast (scope-eligible); the attributes bulk
path follows.

Gates: identical values for every kind (UTF-8, escapes, nils);
scope-owned fills answer the same; path memo unchanged; suite
both modes.

## Outcome (1.9.174.6)

fast_text/comment/cdata content, fast_pi_target/data (the
read_pi_data strip preserved), and fast_path (owned-string copy
+ engine free) — every first-touch content fill now rides the
address faces via @addr_reads_fast (scope-eligible), and the
bulk attribute faces accept scope-owned elements (they touch no
document state; the scope's version stamps the memo).
