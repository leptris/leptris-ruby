# 18 — Audit: spec doubles + gem contents

Status: DONE

- [x] Spec-double scan: zero RSpec doubles/mocks/`allow(` across
      spec/ (the two grep hits are XPath `xs:double` casts inside
      expectation strings). Real documents throughout, per the
      standing convention.
- [x] Gem contents: `TODO.restructure/` does NOT ship in the gem
      (verified by building the gem and listing the tar — 0
      entries; the gemspec's `git ls-files` reject block covers
      it).
