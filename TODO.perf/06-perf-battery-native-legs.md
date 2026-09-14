# 06 — Native-layer legs in the perf battery + drift record

Status: SHIPPED (1.9.163.2) — benchmark/native_vs_binding.rb runs
the walk/read/serialize rows through both surfaces under the
TODO.restructure/17 load gate. Honest findings recorded: warm rows
favor the binding's memoization (attr 0.08 vs 0.30 ms; the native
API pays per-call dispatch with no memo layer); cold one-shot
favors the native API (1.81 vs 2.39 ms — on TOP of the binding's
own bulk/fast acceleration); serialize at parity.

benchmark/ gains native-layer legs (walk/build/attr rows via
NativeNode beside the binding rows) so the drift record tracks
both surfaces; TODO.restructure/17's record gains a native table.

Gate: one command (rake benchmark:all or the two scripts) emits
both tables; load-gated per the shared-machine discipline.
