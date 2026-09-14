# 06 — Native-layer legs in the perf battery + drift record

Status: TODO

benchmark/ gains native-layer legs (walk/build/attr rows via
NativeNode beside the binding rows) so the drift record tracks
both surfaces; TODO.restructure/17's record gains a native table.

Gate: one command (rake benchmark:all or the two scripts) emits
both tables; load-gated per the shared-machine discipline.
