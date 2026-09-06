# 06 — CLAUDE.md architecture map refresh

Status: DONE

The map predated XQuery, ResultText, HTML parsing, the XSLT/XPath
compiled faces, and the copy/evaluation-context seams.

- [x] File map updated (xquery.rb, result_text.rb, xslt.rb,
      xpath.rb, evaluation_context.rb, Document.copy_of seam).
- [x] Conventions now name the constraint set explicitly (no
      respond_to? type checks in lib; send/ivar rules were already
      there).
