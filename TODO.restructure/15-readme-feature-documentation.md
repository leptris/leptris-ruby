# 15 — README: document the three newest features

Status: DONE

- [x] `Node#digest(drop_ws:)` — structural-equality semantics.
- [x] `Element#to_xml(expand_empty: true)` — libxml2
      `NO_EMPTY_TAGS` parity.
- [x] Iterparse lifetime: post-iteration use raises
      `UseAfterFreeError` (IterationScope); `#document` stays nil;
      identity holds within a subtree.
