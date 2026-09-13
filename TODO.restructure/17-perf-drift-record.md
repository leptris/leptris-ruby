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

## 2026-09-13 — recorded (load 5.8, libleptris 1.9.152 / gem 1.9.152.0, Nokogiri 1.19.4, arm64-darwin)

7000-item x 6-element doc (42k elements), best-of-5, cold walk =
best of 3 single-shots on fresh docs:

| row | leptris | nokogiri | ratio |
|---|---:|---:|---:|
| parse | 1.57 ms | 9.85 ms | 6.26x |
| attr reads (over element_children) | 1.12 ms | 2.12 ms | 1.88x |
| text agg (500 content) | 0.06 ms | 0.34 ms | 6.18x |
| serialize | 2.31 ms | 7.49 ms | 3.24x |
| inner_html (200) | 0.71 ms | 2.67 ms | 3.79x |
| children walk (warm) | 0.28 ms | 0.52 ms | **1.86x** |
| element_children walk | 0.17 ms | 0.53 ms | 3.11x |
| COLD children walk | 4.69 ms | 1.58 ms | 0.34x |

Drift vs the 1.9.55 profile: serialize 3.24x held (~3.2x); warm
children-walks flipped from the known ~0.5x loss to a 1.86x WIN
(the SAX/children batch paths + lane-18); element_children from
parity to 3.11x. Cold first-touch walks remain the single loss
(0.34x ~ 3x behind — the wrapper-allocation floor, #147). Parse /
attr / text rows are not directly comparable to the old numbers
(different fixture shape); serialize/inner/walk shapes match.
