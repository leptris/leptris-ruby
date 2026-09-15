# 29 — Namespace-bound xpath on the compiled + eager path

Status: DONE (1.9.174.7)

TODO.perf/15 excluded namespace-bound evaluations from the
compiled-expression cache — they still pay the engine's string
parse per call (~2-3µs) on top of an already-cached ns set. The
engine has leptris_xpath_compiled_eval_ns; route the ns branch
of xpath/at_xpath through the compiled cache (the handle is
ns-independent — compile once) and the cached ns set, then let
the eager materializer (TODO.perf/22) take the result.

Gates: ns-bound results identical (prefix resolution, missing
prefixes raising as today); the version-pinned path untouched;
suite both modes.

## Outcome (1.9.174.7)

The ns branch of xpath/at_xpath rides the compiled-expression
cache (the handle is ns-independent) + the cached ns set via
XPath#eval_ns_ptrs (leptris_xpath_compiled_eval_ns); results
flow into the eager materializer. Measured (load ~16): repeat
ns-xpath 7.9µs -> 3.1µs (2.5x).
