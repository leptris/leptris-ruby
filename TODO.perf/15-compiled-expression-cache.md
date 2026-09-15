# 15 — Compiled-expression cache for Searchable#xpath / #at_xpath

Status: DONE (1.9.163.6)

Searchable#xpath passes the expression STRING to
leptris_xpath_eval each call. The engine caches compiled
expressions by string (measured: repeat-string eval 7.0µs vs
varied-string 34.98µs — the ~28µs is per-call parsing), but the
string path still pays cache lookup + hashing per call. A
compiled handle evaluated directly measured 4.58µs on the same
shape — 34% under the string path.

The binding already exposes XPath.compile (parse once, eval
many). Add a bounded LRU keyed on the expression string inside
Searchable: plain (no version pin, no ns bindings) xpath/at_xpath
evaluations route through cached compiled handles. Cache only
successful compiles; bounded (~64 entries, Hash#shift eviction);
GVL makes the Hash ops safe.

Gates: xpath/at_xpath results identical (nodesets, scalars,
empty results); invalid expressions still raise XPathError;
namespace-bound and version-pinned paths unchanged; repeat-call
rows improve ~30%.

## Outcome (1.9.163.6)

Searchable.compiled_expression: bounded LRU (64 entries, Hash#shift
eviction, LRU refresh on hit) keyed on the expression string;
plain xpath/at_xpath evaluate cached compiled handles via
XPath#eval_ptrs (leptris_xpath_compiled_eval). Failed compiles
never cache (fall back to the string entry so the error surface
is unchanged); version-pinned and namespace-bound paths keep
their dedicated entries. Measured: repeat at_xpath 3.7us ->
1.9us under load 17-30 (~2x); CSS rides it automatically
(deterministic translation -> same key).
