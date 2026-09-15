# 08 — Version-coherent native mutations (#204 ask 2)

Status: TODO

The native builder factories (create_element/text/child, add_child,
set_root) do not advance the binding Document's mutation version —
a binding children read after a native attach serves the STALE
memo. Fix in the ext: every mutating entry calls the document's
advance_version (cached ID) after the C mutation, and the readonly
gate before it. Mutations are cold relative to reads, so the two
rb_funcall hops are fine. Gate: build via native factories, read
via binding children/element_children — lists must agree.
