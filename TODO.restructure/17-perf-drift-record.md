# 17 — Perf drift record on the current build

Status: DONE

- [ ] **Blocked on a busy shared host.** The machine has been at
      load 30–180 for days — every battery attempt this week has
      been a load-induced fiction (Nokogiri's own baseline swings
      3× run-to-run on this box, e.g. 16→27→58 ms for parse). The
      standing baseline from the clean 1.9.76 window still holds:
      parse 10–12×, serialize 2.9–3.2×, inner_html 4–5×, attr reads
      6–9×, text 9–11×, element_children walks at parity. Will
      re-record on the next clean window (load < 15).

## Re-recorded 2026-09-21 — clean window (load ~12, 1.9.210.0, 84k-element/1.3MB catalog, interleaved best-of-5, nokogiri 1.19.4)

- [x] Standing harness (MEDIUM fixture): parse medium **11.1x** /
      small 1.88x; xpath 2.4-20x (predicate 15-20x, complex
      11-14x); traverse 1.5-1.7x; serialize 2.25-3.13x
- [x] Warm `children` walks **2.06-2.08x** (was 1.86x at 1.9.152)
- [x] Cold parse+first-touch walks **0.58-0.74x (avg ~0.66x)** —
      the loss nearly HALVED from 0.34x; the engine's
      document-block/arena work (1.9.210) shows here
- [x] Attr cold row (fresh wrappers) 1.18x
- [ ] **Open front: cold TEXT row 0.66x** — fresh text-node
      materialization (`element_children.each(&:content)` cold)
      loses where warm text aggregation was 6.18x. Next perf
      round's target.
