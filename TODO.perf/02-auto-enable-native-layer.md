# 02 — Auto-enable the native layer when the bundle is present

Status: SHIPPED (1.9.162.9) — require "leptris" quietly
probes for the native bundle and activates when present.
LEPTRIS_NO_NATIVE=1 forces the FFI path (suite exercises both).
The explicit native_layer require remains the parallel-API entry
for NativeNode builders.

Today `require "leptris/xml/native_layer"` is opt-in. End-state:
`require "leptris"` quietly probes for the vendored native.bundle
and, when present, activates the acceleration (01 makes the
default classes benefit). Silent fallback to FFI when absent
(ruby-variant on TruffleRuby/JRuby, custom builds). The explicit
native_layer require remains the parallel-API entry
(NativeNode builders).

Requires: 01 (so auto-enable accelerates the DEFAULT API, not a
parallel one), and a divergence test — same specs pass in both
modes (the suite already runs both; make it explicit).
