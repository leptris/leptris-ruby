# 12 — #153: merge the ResultAttr wrap (PR #154)

Status: DONE

- [x] Reviewed the diff: autoloads `ResultAttr` per the rule,
      extends the materialization capture (name+value at result
      lifetime) symmetric to `ResultText`, no constraint
      violations.
- [x] CI 10/10 — merged ahead of this round's branch so the
      release carries it.
- [x] Verified `doc.xpath("//item/@id").first.name/.value` on the
      merged build; #153 closed with the verification.
