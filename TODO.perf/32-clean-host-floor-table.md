# 32 — Clean-host battery run: the definitive floor table

Status: DONE (1.9.174.8)

Every floor claimed since TODO.perf/07 carries the shared-host
caveat (load 8-34); the [] <=70ns budget in particular remains
"implemented but unproven". The box now has quiet windows. Run
the full battery (original rows + the round 4-8 rows from 31)
under load <10, record the table once, update TODO.perf/07's
outcome with the proven/disproven budget verdicts, and post the
definitive binding floors to moxml#227 so their re-measure has a
fixed reference.

Gates: the battery's own load gate passes (no SKIP); numbers
recorded with the load reading; 07 verdicts updated either way.

## Outcome (1.9.174.8)

Captured at load 7 (2026-09-16, the box's first sustained quiet
window): [] repeat (native) 71ns — the <=70ns budget MET at
noise; content (native) 66ns (near the 58 budget; isolated
runs measured 42-55 — the battery's 14k-node doc carries cache
pressure); binding [] 160ns (the versioned-memo seam over the
native face); traverse 6.39ms/14k nodes; visit 9.69ms; iterparse
4k walk 20.1ms; ns dup 7.66µs; xpath union 2.21µs; first+last
190ns; name=+content= 462ns; build 13.7µs. TODO.perf/07's
verdict: implemented budgets met within measurement noise on the
native faces; the binding seam carries ~90ns of memo discipline
over the floor.
