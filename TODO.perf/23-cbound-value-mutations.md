# 23 — C-bound name= / content= / unlink

Status: DONE (1.9.174.4)

The value mutations still run ensure_writable! + FFI marshaling
per call (~450ns): Element#name=, Element#content=,
Text#content=, and Node#unlink (transforms rename, rewrite, and
remove nodes constantly). Same face shape as set_binding_attribute:
gates + version bump + engine write in one dispatch —
set_binding_name (element names), set_binding_text (element text
or text-node content, kind-dispatched in C), and
unlink_binding_node (plus the Ruby-side @parent clear and memo
invalidations that ride the version bump).

Gates: rename/content/unlink semantics unchanged (memos, sibling
stamps, path memo all invalidate through the version bump);
readonly raises through every face.

## Outcome (1.9.174.4)

Native.set_binding_name / set_binding_text (kind-dispatched
element-vs-text) / unlink_binding_node — gates + bump + engine
write in one dispatch, wired into Element#name=, #content=,
Text#content=, and Node#unlink (@parent clear and memo
invalidation ride the version bump). Measured (load ~11):
name= 237ns, content= 298ns, unlink+re-add 1.74µs; readonly
raises verified through every face.
