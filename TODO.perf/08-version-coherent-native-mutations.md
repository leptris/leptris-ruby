# 08 — Version-coherent native mutations (#204 ask 2)

Status: DONE (1.9.163.5)

The native builder factories (create_element/text/child, add_child,
set_root) do not advance the binding Document's mutation version —
a binding children read after a native attach serves the STALE
memo. Fix in the ext: every mutating entry calls the document's
advance_version (cached ID) after the C mutation, and the readonly
gate before it. Mutations are cold relative to reads, so the two
rb_funcall hops are fine. Gate: build via native factories, read
via binding children/element_children — lists must agree.

## Outcome (1.9.163.5)

document_advance_version moved from two rb_funcall hops to direct
ivar reads/writes (@readonly Qtrue check, @version Fixnum bump) —
no method dispatch on the mutation path. Every NativeNode
mutating entry (create_child, append_child/add_child, set_root)
and the new C-bound binding faces (append_binding_child,
set_binding_attribute) run the same gate: UseAfterFreeError via
the nil @c_address twin, ReadOnlyError via @readonly, then the
bump. Gate verified: native append -> binding children/content
serve fresh values; readonly raises through every native entry.
