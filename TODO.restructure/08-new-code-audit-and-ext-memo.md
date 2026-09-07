# 08 — 1.9.100-round code audit + expand_empty ext memo

Status: DONE

- [x] Constraint audit over the 1.9.100 additions (digest,
      expand_empty): no send/ivar/respond_to?/require violations;
      autoload set complete.
- [x] `Serialization.element_xml_expand_empty` allocated a fresh
      `SerializeExtStruct` per call — memoized to an
      `EXPAND_EMPTY_EXT` constant, mirroring the `INDENT_TEXT_EXT`
      discipline (allocation-free steady state).
