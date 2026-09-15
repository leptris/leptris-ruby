# 13 — Version-stamped structural memos: root/parent/siblings (+ FFI-mode stale-@parent fix)

Status: DONE (1.9.163.6)

Document#root re-derives (FFI + wrap) on every call — every
pipeline entry pays it. Node#parent and the sibling hops
(next_sibling/previous_sibling) pay FFI + Node.wrap per call, so
Nokogiri-style sibling-advancement loops pay ~300ns/hop.

BUG found while designing this: in FFI mode the children walk
seeds @parent, and a later move (add_child to another parent)
leaves the stale @parent — child.parent answers the OLD parent.
Native mode masks it (the bulk path does not seed @parent). The
version-stamped memo fixes both modes: derive once, stamp with
the owning document's mutation version, re-derive after any
mutation that bumps it.

Design: parent memoizes only for document-owned nodes
(scope-owned iterparse elements keep deriving — a scope element
adopted into a document moves without its scope's version
advancing, so a stamp would lie). Cross-document adoption bumps
BOTH documents' versions (the source document's other nodes hold
sibling/parent stamps that the move invalidates); the moved
node's stamps clear at the mutation site. next_sibling /
previous_sibling memoize the same way. Document#root memoizes
against the document's own version (root= bumps it; free clears).

Gates: parent correct after same-doc and cross-doc moves in BOTH
modes (the FFI staleness becomes a spec); sibling chains correct
around unlink/insert; root identity stable; traversal-loop rows
improve.

## Outcome (1.9.163.6)

Version-stamped memos on Document#root (pure ivar compare, ~82ns
under load 17), Node#parent / next_sibling / previous_sibling
(~72-76ns memo hits vs ~300-500ns deriving; @structure_memoizable
computed once at construction — including the C-constructed
wrappers — keeping the hit path free of method dispatch). The
FFI-mode stale-@parent bug is FIXED (spec-pinned: parent correct
after same-doc and cross-doc moves; the seed stamps only
constructor-KNOWN parents — nil constructor parent means unknown,
because the engine may attach during creation, e.g. create_child).
Cross-document moves clear the moved node's stamps and advance
the SOURCE document's version. The adoption-lift ancestor walk
uses Node#unstamped_parent: deriving a stamped parent between the
version bump and the engine move would record post-bump versions
carrying pre-move truth. Scope-owned iterparse elements never
memoize.
