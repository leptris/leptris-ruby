# 05 — README: Memory section (#147 resolution, option A)

Status: DONE

- [x] Document the two findings from leptris-ruby#147:
      finalizer semantics (objects stay `uncollectible` until the
      async finalizer queue drains — retention tests must yield
      wall-clock time, not just `GC.start`) and the held-workload
      profile (wrappers ~+552 kB/doc vs the C tree's +456 kB;
      ~1.57x Nokogiri held) as the documented cost of the
      FFI-only architecture.
- [x] Note the TypedData trade-off and the open option (A/B/C) on
      the issue for the maintainer.
