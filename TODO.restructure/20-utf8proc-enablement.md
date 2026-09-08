# 20 — utf8proc enablement (fn:normalize-unicode in the platform gems)

Status: DONE (shipped 1.9.107.2)

## Finding (validated on this machine)

- `LEPTRIS_ENABLE_UTF8PROC=ON` builds cleanly (linked against
  homebrew utf8proc 2.11.3) and is what the function needs.
- **The blocker**: FindUtf8proc links the SYSTEM library with an
  ABSOLUTE install path (`/opt/homebrew/opt/utf8proc/lib/
  libutf8proc.3.dylib`) — a platform gem built this way fails to
  load on any machine without utf8proc at that exact path. The
  platform gems' self-containment would be broken.

## Plan (the properly-engineered greenlight)

- [x] Build utf8proc from its release source in `rake compile`
      (same tarball discipline as libleptris), per platform.
- [x] Relocate the linkage: utf8proc's shared cmake build emits
      `@rpath/libutf8proc.3.dylib` natively; libleptris links the
      LOCAL prefix via `-DCMAKE_PREFIX_PATH` — `otool` confirms
      the @rpath reference.
- [x] Vendor `libutf8proc.3.{dylib,so}` (SONAME file) beside
      `libleptris.*` in the platform gems; ffi.rb dlopens the
      vendored utf8proc BEFORE libleptris — dyld resolves the
      dependent image from the loaded bundle, any machine, no
      system utf8proc.
- [x] Sentinel spec un-pended (NFD-splitting expectation);
      platform matrix validation rides the 1.9.107.2 CI legs
      (isolated binding-patch release so a revert is clean).

Not landing this half-working: a utf8proc-linked gem that fails to
load on utf8proc-less machines would be worse than the missing
function.
