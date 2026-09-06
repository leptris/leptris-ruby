# 03 — Evaluation-context seam for the expression faces

Status: DONE

`XPath#eval` and `XQuery#eval` each hand-rolled "resolve a Document
or Element receiver into (owning document, context-node pointer)"
with their own argument errors — duplicated logic, drift-prone as
faces multiply (XPath / XQuery / future).

## Change

- [x] New `Leptris::XML::EvaluationContext` (autoloaded from
      `lib/leptris/xml.rb`, per the autoload rule): a value object
      with `.of(receiver)` and `#document` / `#context_node_ptr`
      readers; raises ArgumentError for anything but a Document or
      Element — one typed seam.
- [x] `XPath#eval` and `XQuery#eval` resolve through it; their
      private duplicated resolvers removed.
