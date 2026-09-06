# 04 — Spec MECE: one domain per file

Status: DONE

The lockstep rounds accreted specs into whichever file was open:
`xquery_spec.rb` carried HTML-parsing and pure-XPath blocks;
`document_spec.rb` carried the HTML suite. Reorganized by domain —
count-neutral moves only, no example text changed.

## Moves

- [x] All HTML specs (`parse_html` behaviors, characterization
      gates, head-content lift, PI constructs) → new
      `spec/xml/html_spec.rb`.
- [x] Pure-`#xpath` blocks (XPath 3.1 value-level surface, 2.0
      ledger, type operators, format-number, analyze-string,
      catalog slices) → `spec/xml/xpath_spec.rb`.
- [x] `xquery_spec.rb` now contains only the XQuery face;
      `document_spec.rb` only Document behaviors.
- [x] Total example count unchanged before/after (audit gate).
