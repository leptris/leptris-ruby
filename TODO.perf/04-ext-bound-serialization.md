# 04 — Serialization buffer cycle in C

Status: TODO

FFI.serialize_into_string does the two-call sized protocol
(needed probe, then copy) with Ruby-side buffer management per
to_xml call. Bind the cycle in the ext: one C function taking the
ffi_function pointer + node address, returning a Ruby String.

Gate: serialize row (3.24x baseline) improves; c14n specs
byte-identical.
