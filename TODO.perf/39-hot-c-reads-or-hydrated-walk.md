# 39 — Hot reads: C-defined parameterized readers, or the hydrated columnar walk

Status: QUEUED (leptris-ruby#622, ask 1)

Source: the moxml-on-leptris facade's structural-row losses, all at
the per-read/per-mint Ruby floor. Facade reads sit at ~331ns because
every read is an `UnboundMethod#bind_call` (one Ruby frame). The
proven budgets (TODO.perf/32, clean host): native `[]` 71ns, binding
memo seam ~160ns. The 2x-reads finish line needs the last Ruby frame
gone. Two acceptable shapes — the owner picks:

- **(a)** a binding-side C API that defines hot instance methods on
  arbitrary receiver classes, operating on the receiver's TypedData
  struct — the shape #204's closure sketched ("C-defined hot methods
  parameterized by subclass"). moxml's Identity classes (subclass
  NativeNode, klass-injected via `NativeNode.from`) get C
  `[]`/`name`/`content`/`attribute` readers; the platform matrix
  stays on the leptris dependency (moxml remains pure-Ruby).
- **(b)** extend `walk_columnar` (TODO.perf/32's face) to a
  **hydrated** walk: the same single crossing returns, per row, the
  flat attr packet + text content alongside names/handles/depths.
  The consumer pipeline (walk + attribute + text reads) then pays
  zero per-read calls — the reads ride the walk crossing.

Unlocks: walk+read (warm) 0.67x, walk+read (cold) 0.37x, children
recursion (cold) 0.46x of raw nokogiri.

## Evidence

- lutaml/moxml scoreboard baseline (v0.5.166-era, clean host,
  interleaved A/B per the published protocol).
- TODO.perf/32's clean-host floor table: `[]` 71ns native / 160ns
  binding seam.
- leptris-ruby#527's verdict: the engine line is flat — the cold-row
  cost is binding/facade, not an engine regression.
