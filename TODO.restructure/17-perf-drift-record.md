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
