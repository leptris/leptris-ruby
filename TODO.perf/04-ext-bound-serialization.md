# 04 — Serialization buffer cycle in C

Status: SHIPPED (1.9.163.1) — the sized-buffer cycle runs in C
(probe largest owned buffer first: single serialization for
big docs; grow-only scratch under the GVL). inner_html 84->50ms
(1.7x per-call batch); doc serialize at parity with the FFI seam
(both single-call); encoding: paths keep the FFI options path.

FFI.serialize_into_string does the two-call sized protocol
(needed probe, then copy) with Ruby-side buffer management per
to_xml call. Bind the cycle in the ext: one C function taking the
ffi_function pointer + node address, returning a Ruby String.

Gate: serialize row (3.24x baseline) improves; c14n specs
byte-identical.
