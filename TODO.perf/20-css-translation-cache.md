# 20 — CSS translation cache

Status: DONE (1.9.174.3)

Searchable#css/#at_css run CssToXPath.convert on every call —
pure Ruby regex/string work (~300ns+) — before the compiled-
expression cache (TODO.perf/15) can hit on the result. The
translation is a pure function of (selector, prefix); cache it
with the same bounded-LRU shape (64 entries, Hash#shift
eviction, GVL-safe), so repeat selectors skip straight to the
compiled handle.

Gates: css/at_css results identical; repeat-call rows improve by
the translation cost; the join in xpath()'s expression build is
also skipped for the single-String-path shape (join minted a
fresh String per call even for one path).

## Outcome (1.9.174.3)

Searchable.css_expression: bounded LRU (64, shared limit) keyed
on prefix+selector; css/at_css translate through it so repeat
selectors skip the regex machinery straight to the compiled-
expression cache. The single-String-path shape of xpath/at_xpath
no longer joins (join minted a fresh String per call).
