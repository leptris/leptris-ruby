# 19 — .gitignore hygiene for build artifacts

Status: DONE

- [x] `.rspec_status` (RSpec's example-status artifact) ignored —
      it was showing as untracked noise in every round.
- [x] `*.gem` was already covered; a stray locally-built gem from
      this round's contents check removed (one I created; the
      unrelated `taurus-0.1.0.gem` predates this repo work and was
      left untouched).
