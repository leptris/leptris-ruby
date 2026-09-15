# 30 — dup one-dispatch + first/last element child faces

Status: DONE (1.9.174.7)

Node#dup runs create + FFI element_copy + root= (three dispatches
plus the lift-guard walk) for an engine-copier op that is already
2.3x — bind the whole copy: engine create + handle + element_copy
+ root wrap in one face. And the element-child readers pay O(N):
first_element_child scans siblings with two FFI calls per
non-element (text-heavy parents), last_element_children batches
ALL children to keep one — one C walk each answers in a single
dispatch.

Gates: dup semantics (comment/PI children, namespaces — the
copy_of seam contract #696/#721/#812); first/last on mixed
content, empty elements, document receivers; suite both modes.

## Outcome (1.9.174.7)

Native.copy_binding_element: engine create + lifetime handle +
document wrapper + element_copy + rooted+memo-seeded wrap in one
dispatch; the namespace-lift decision stays in Ruby (skip_
adoption_lift? + lift — the copy_of seam's #696/#721/#812
semantics), and the return shape matches copy_of's contract (the
copied root ELEMENT — my first version returned the document and
the probe caught it). Native.first/last_element_child: one C
walk each (the FFI scan paid two calls per skipped sibling; the
batch fetch materialized every child to keep one). Measured
(load ~16): ns-bearing element dup 37.0µs -> 9.6µs (3.9x);
first_element_child over 1000 mixed children 98ns (memo-hit
shape), last 3.2µs cold-walk.
