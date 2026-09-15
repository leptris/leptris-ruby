# 11 — The #204 gap table as a battery leg

Status: DONE (1.9.163.5)

Reproduce moxml's gap table rows locally (parse 30KB, to_xml,
[] / content / name reads, set_attribute, create x2 + attach,
typed walk) in benchmark/native_vs_binding.rb so every perf round
tracks the exact rows the 2x mandate measures — both surfaces,
interleaved, load-gated.

## Outcome (1.9.163.5)

benchmark/native_vs_binding.rb gained the gap rows: []/content/
name repeat reads (binding + native), set_attribute, and the
build (create x2 + attach) row, all interleaved best-of behind
the file's load gate (skips > 20). `set_attribute` itself became
a C-bound face this round (Native.set_binding_attribute: gates +
version bump + engine write in one dispatch).
