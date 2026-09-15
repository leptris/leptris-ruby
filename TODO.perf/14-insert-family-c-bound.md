# 14 — C-bound insert family + cold-[] native fill

Status: DONE (1.9.163.6)

add_child and []= are C-bound (TODO.perf/08-09); prepend_child,
add_next_sibling, and add_previous_sibling still run the full
Ruby path (ensure_writable + eager-namespace guard ordering +
FFI). One C face with a mode int covers all engine insertions
(append/prepend/insert_after/insert_before — same
int(void*, void*) ABI): gates + predicate + version bump + engine
insert in one dispatch, Qnil fallback when the child needs the
namespace lift, exactly like append_binding_child.

Also: the completely-cold branch of Element#[] fills through
leptris_element_attribute (FFI) while the partial-memo branch
above it uses the native face — the cold path should ride the
native face too (~150ns per first-touch attribute read).

Gates: insert semantics unchanged (specs exist for sibling
inserts); namespaced children still lift; readonly raises.

## Outcome (1.9.163.6)

Native.insert_binding_child(document, anchor, child, mode): 1
prepend / 2 after / 3 before — gates + predicate + version bump +
engine insert in one dispatch, Qnil fallback to the Ruby lift
path. prepend_child / add_next_sibling / add_previous_sibling
carry the fast branch + cross-document invalidation. The
completely-cold Element#[] first-touch fill rides the native face
(matching the partial-memo branch). Specs: ordering, lift
fallback, readonly raise.
