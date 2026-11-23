# The native-layer contract (leptris / yeptris / teptris)

The three ruby suites ship one native story. This document is the
contract; every suite's loader, packaging, and CI gates derive from
it. Divergence is a bug — file it against this repo.

## 1. The FFI face (always present)

The FFI surface is the fallback of last resort and the only face on
unsupported platforms. Its library resolution order is normative:

1. `ENV["<PKG>_LIB_PATH"]` — an explicit full path (or directory).
2. The vendored tree: `lib/<pkg>/vendor/<platform>/libleptris.{dylib,so,dll}`.
3. The flat layout: `lib/libleptris.{dylib,so,dll}` (linux platform
   gems pack utf8proc flat here too).
4. System paths: `/usr/local/lib/libleptris.{dylib,so}`.
5. The bare soname (`leptris`) — the system linker search, last.

The candidate list is a SINGLE SOURCE OF TRUTH shared by every face
that loads the library. Two differently-pathed copies load as two
images with split per-document state — never resolve through a
second list.

utf8proc (when vendored) is dlopen'd BEFORE the engine on darwin
(@rpath dependency resolution), with the flat `lib/` spellings tried
on linux; absence is not an error.

A missing library raises with the NAMED REMEDY (which gem variant
was installed and the command that fixes it) — never a bare
LoadError.

## 2. The per-minor native read layer (accelerated face)

- One compiled bundle per Ruby minor, DOT-FREE:
  `native_<major>_<minor>.so` (`.bundle` on darwin, one DLL per
  minor on Windows — a PE DLL must bind its build Ruby's runtime).
- MRI derives the init symbol from the basename cut at the first
  dot: `native_3_4.so` resolves `Init_native_3_4`.
- **No unversioned fallback, ever.** A bundle built by any other
  minor is a wrong-ABI load (the compiled-in RString layout changed
  in 3.2 — the 3.1 segfault class). An absent variant raises, and
  the top-level require falls back to the FFI face with a warning.
- The bundle resolves libleptris through the SAME candidate list as
  the FFI face (`lib_candidates`).

## 3. Packaging

- Platform gems: the vendor tree + one bundle per supported minor.
  The supported-minor list is a single constant (SUPPORTED_MINORS)
  consumed by the build matrix, the packaging loop, and CI — never
  inlined per-job.
- Source (ruby-platform) gems: full engine + utf8proc + ext sources
  so users compile at install; no vendored binaries.
- Windows: one DLL per minor, built per minor before packaging.

## 4. The gates (CI is the only validator)

- **glibc floor**: the gnu linux gems must bind ≤ GLIBC 2.31 — the
  release asserts the max symbol version from the built artifact
  (`strings lib*.so | grep -oE 'GLIBC_2\.[0-9]+' | sort -uV | tail -1`)
  and fails naming the bound version. Build in old-glibc containers
  (bullseye per Ruby minor); never on floating ubuntu images.
- **Engine-lockstep refusal**: the build fetches the engine at the
  pinned tag and FAILS the release when the tag does not exist —
  a stale-pin release must be structurally impossible.
- **Version lockstep**: versions are `{engine-semver}.{binding-patch}`;
  the engine pin moves in the same wave as the release it needs.
- **Artifact verification**: every release verifies the shipped
  artifact BY BEHAVIOR/CONTENT on the registry (download, strings,
  run) — a merged PR with a stuck workflow is not a release.

## 5. What the sisters adopt

yeptris-ruby and teptris-ruby converge onto this contract:
the vendor-tree layout, the candidate order, the per-minor
DOT-FREE bundle naming with no unversioned fallback, the flat-lib
linux utf8proc spellings, the named-remedy error, the gates above.
Their divergences (flat `native_<minor>.so` at lib/ root,
`<minor>/native.so` subdirs, ext-only layouts) migrate to the
canonical shapes; the migration is mechanical and each suite's CI
gates prove it.
