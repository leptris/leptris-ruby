# 09 — Adoption-lift fast path + binding create via C (#204 ask 3, #149 continuation)

Status: DONE (1.9.163.5)

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

## Outcome (1.9.163.5)

Three layers landed:
1. `Element.skip_adoption_lift?` — non-elements skip outright
   (lift no-ops them anyway); elements consult
   `Native.ns_lift_needed?` (two C calls: own-declaration count +
   resolved URI). Hoisted ABOVE the target's `namespaces`
   materialization at all five mutation sites (add_child,
   prepend_child, both sibling inserts, root=) — a fresh parent
   no longer pays the in-scope collection FFI round-trips per
   attach. Measured effect: add_child on a fresh parent
   1678 -> 506ns.
2. `Native.create_binding_element/text` build the binding wrapper
   in C (one C call + wrapper + identity-cache store; no FFI
   marshaling). Document.create/create_element/create_text_node
   route through them when auto-enabled.
3. `Native.append_binding_child` — gates + predicate + version
   bump + engine append in ONE dispatch (Qnil = child needs the
   lift, Ruby falls back). Element#add_child's node branch uses
   it; namespaced children still lift (spec-pinned). The #204
   ask-3 shape (create x2 + attach) went 4.1us -> ~1.2us measured
   under host load 12-19 — at or past the Nokogiri row (1.5us).
