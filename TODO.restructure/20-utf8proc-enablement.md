# 20 — utf8proc enablement (fn:normalize-unicode in the platform gems)

Status: IN PROGRESS — mechanics validated, engineering plan set
(owner greenlight 2026-09-08)

## Finding (validated on this machine)

- `LEPTRIS_ENABLE_UTF8PROC=ON` builds cleanly (linked against
  homebrew utf8proc 2.11.3) and is what the function needs.
- **The blocker**: FindUtf8proc links the SYSTEM library with an
  ABSOLUTE install path (`/opt/homebrew/opt/utf8proc/lib/
  libutf8proc.3.dylib`) — a platform gem built this way fails to
  load on any machine without utf8proc at that exact path. The
  platform gems' self-containment would be broken.

## Plan (the properly-engineered greenlight)

- [ ] Build utf8proc from its release source in `rake compile`
      (same tarball discipline as libleptris), per platform.
- [ ] Relocate the linkage: rebuild utf8proc with a relocatable
      install name, and re-link libleptris against the LOCAL build
      (not the system one) — `-DCMAKE_PREFIX_PATH` to the local
      utf8proc install.
- [ ] Vendor `libutf8proc.{dylib,so,dll}` beside `libleptris.*` in
      the platform gems; `ffi_lib` pre-loads utf8proc before
      libleptris so dyld resolves the dependent image from the
      already-loaded bundle.
- [ ] Un-pend the `normalize-unicode` sentinel spec; validate the
      full platform matrix in CI before releasing (isolated
      `{C}.1` release so a revert is clean).

Not landing this half-working: a utf8proc-linked gem that fails to
load on utf8proc-less machines would be worse than the missing
function.
