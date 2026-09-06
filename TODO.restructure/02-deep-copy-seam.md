# 02 — Deep-copy seam: one authority for "copy as a new document's root"

Status: DONE

The create-document → element_copy → wrap → attach-as-root sequence
was duplicated in three places (`Node#dup`, `Element#dup`,
`Serialization.to_xml_element_unit`) — a DRY/MECE violation with
drift risk (it already drifted twice across the #696/#721/#812
rounds).

## Change

- [x] `Leptris::XML::Document.copy_of(element)` — the single
      authority: creates the target document, C-copies the element,
      wraps, attaches as root, returns the copy (model-driven: the
      Document owns its construction semantics).
- [x] `Node#dup` / `Element#dup` / `to_xml_element_unit` delegate
      to it; the three inline copies removed.
- [x] Existing dup/copy specs (byte-parity, namespaces, comment/PI,
      detached-from-original, #130 flatness) all pass unchanged —
      behavior-neutral by construction.
