# 22 — SAX drain: bulk kind strip (the 0.77-0.93x row)

Status: DONE — timing gate PASSED (2026-09-09, load ~14)

The moxml table shows SAX at 0.77-0.93x Nokogiri (it fully won at
the 1.9.40-era battery). Investigation under load-404 conditions
(timing unusable; allocation profiling is load-independent):

- **Allocations are NOT the gap** — measured GC-stat deltas:
  text-only 32,381 vs Nokogiri's 400,061 allocs/parse (12x fewer);
  all-events 112,440 vs 400,034 (3.6x fewer).
- **The time cost was per-event FFI crossings in the drain**: the
  kind strip was read with a `get_uint8` per EVENT (all events,
  dispatched or not — a memory crossing each) after the
  whole-record-unpack was retired for its 2.25M-Integer profile.
- **Fix**: the kind strip reads in ONE `get_bytes` + ONE `unpack`
  per drain through the already-defined memoized
  `KIND_TEMPLATE_FOR` — kind codes 0..10 unpack to IMMEDIATE
  Fixnums (zero allocation), so this strictly removes ~count FFI
  crossings per drain with no new allocations. Per-dispatched-event
  field reads (2-3 `get_uint32`) remain.

- [x] Bulk strip restored; SAX suite green; allocation profile
      re-verified (32k/112k vs 400k/400k).
- [x] **Timing verification PASSED** (load ~14 window, min-of-7):
      text-only 16.1 vs 169.3 ms = **10.51x faster**; all-events
      146.9 vs 188.6 ms = **1.28x faster**. The moxml 0.77-0.93x
      row is fully inverted on the raw binding.
