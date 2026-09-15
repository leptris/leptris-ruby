# 19 — Lazy FFI::Pointer on wrappers

Status: DONE (1.9.174.3)

Every binding wrapper stores an FFI::Pointer (@c_ptr), and the C
construction faces mint one per node via
rb_funcall(FFI::Pointer, :new) — ~200ns plus a Ruby object and
its GC visit per node, paid at creation even though most nodes'
Pointers are never read (the hot reads are memoized or go through
the address-based native faces).

Store @c_address (Integer) as the canonical truth on every
wrapper; `c_ptr` becomes a lazy materializer
(@c_ptr ||= FFI::Pointer.new(@c_address)) preserving the public
API. Internal call sites: `@c_ptr.address` collapses to
@c_address (also skipping the #address dispatch), and remaining
internal @c_ptr reads go through the c_ptr reader (same cost as
the old attr_reader). The C faces stop constructing Pointers
entirely — they already hold the address.

Gates: suite green both modes (a missed site fails loudly — nil
to FFI raises TypeError); wrapper identity and c_ptr stability
unchanged; creation faces drop ~200ns and one allocation per
node; fresh-doc build row improves accordingly.

## Outcome (1.9.174.3)

@c_address is the canonical truth on every Node wrapper; c_ptr
materializes lazily (@c_ptr ||= FFI::Pointer.new(@c_address)),
preserving the public API and identity. All internal @c_ptr
reads became c_ptr reader calls; the 15 @c_ptr.address sites
collapsed to @c_address (also skipping the #address dispatch).
The C construction faces (create element/text, bulk children,
every xpath materialization) stopped minting Pointers entirely —
one allocation and ~200ns saved per node, and proportionally less
GC. Document keeps its eager reader (documents are few).
Measured under host load 22-25: GC-amortized Document.create
~5-6µs -> ~4.0µs; NativeNode#[] 78ns (budget 70 — clear at
load <10), content 45ns (budget 58 met).
