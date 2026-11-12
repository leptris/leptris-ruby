# 40 — NodeSet.from_result: klass-injected result materialization

Status: QUEUED (leptris-ruby#622, ask 2 — the #204 ask, refiled)

`xpath_result_rows_bulk` crosses once but still mints wrappers in a
Ruby loop (~1.4us/query ask from #204). Mint the result rows in C
with klass injection so consumers receive their wrapper classes
directly.

Unlocks: xpath `//field` (each) 0.59x of raw nokogiri.
