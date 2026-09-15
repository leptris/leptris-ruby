# 27 — C-yield traversal (traverse/visit without the FFI::Function closure)

Status: DONE (1.9.174.6)

Node#traverse and #visit allocate an FFI::Function closure per
call (~1µs) and dispatch every visited node back through the
Ruby closure — the dominant per-node cost of whole-subtree
iteration, paid even on small subtrees where the walk itself is
microseconds.

Bind both to C callbacks that rb_yield directly: the ext's
traverse face keeps the abort-at-self post-order contract and
the exception discipline (rb_protect in the callback stashes,
aborts the walk, re-raises after — exactly the Ruby version's
contract); visit keeps its (node, entering, depth) callback
shape with the same stash-and-raise treatment. Node wrapping per
visit rides the shared binding construction (identity cache +
kind dispatch), and the walk state lives on the C stack — no
globals, nested traversals safe.

Gates: post-order sequence identical (receiver last); the
subtree boundary holds (abort-at-self); block exceptions
re-raise after the walk stops; enum_for forms unchanged; suite
both modes.

## Outcome (1.9.174.6)

Native.traverse_binding / visit_binding: C callbacks that
rb_yield directly (block forwarded explicitly — rb_yield needs
it on the C entry's frame). traverse keeps post-order +
abort-at-self + stash-abort-raise (rb_protect in the callback,
walk state on the C stack — nested traversals independent);
visit keeps (node, entering, depth) with the engine's
(user, node, ...) callback order. Two bugs found by the suite:
the visit callback's argument order (user first — the segfault
spec caught it) and the block forwarding. Measured (load 34):
traverse over 8k nodes 1663.5µs (FFI closure) -> 379.9µs
(4.4x; 6.81x Nokogiri); visit 2288.6µs -> 545.4µs (4.2x).
