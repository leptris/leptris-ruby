# 09 — Adoption-lift fast path + binding create via C (#204 ask 3, #149 continuation)

Status: TODO

Binding create x2 + attach measured 4.1us vs Nokogiri 1.5us. The
#178/#208 namespace lift + pruning runs on EVERY attach and costs
several FFI round-trips (own definitions, prefix read, in-scope
walk) even when it is a provable no-op. Add a one-dispatch C
predicate `Native.ns_lift_needed?(addr)`: false when the node
carries no namespace declarations AND its name has no prefix —
the overwhelmingly common programmatic-build shape. add_child and
friends skip the lift entirely on false. Also route binding
create_element/create_text_node through the ext (one C call +
binding-wrapper construction in C — no FFI marshaling) when
auto-enabled.
