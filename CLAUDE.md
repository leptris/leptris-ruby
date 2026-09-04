# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`leptris-ruby` is the official Ruby binding for `libleptris`
(https://github.com/leptris/leptris), a pure-C99 XML 1.0 parser with a
W3C-conformant XPath 1.0 engine (438/438 on the W3C suite), full SAX,
pull parsing, and C14N. The binding is **FFI-based** (no C extension,
no compilation at install) and ships **precompiled platform gems**
with the shared library vendored inside: x86_64/aarch64-linux (glibc
and musl), x86_64/arm64-darwin, x64-mingw32/ucrt, aarch64-mingw-ucrt,
plus the pure-Ruby fallback gem.

Version lockstep: the gem's version is `{c-full-semver}.{patch}` —
the pinned libleptris release plus a binding-local patch counter
(`libleptris 1.9.76` <-> `leptris 1.9.76.0`; a binding-only fix
against the same pin -> `1.9.76.1`, patch resets when the pin
moves). Same scheme as the Python binding. A C release means one PR
carrying version.rb + the Rakefile `LIBLEPTRIS_VERSION` pin + the
CHANGELOG entry, then the release workflow.

## Commands

```bash
bundle exec rake compile   # build libleptris (pinned tarball) into lib/
bundle exec rspec          # full suite (uses the vendored library)
bundle exec rspec spec/xml/xpath_spec.rb:42   # one example
bundle exec rake gem:native:arm64-darwin      # platform gem
```

`LEPTRIS_LIB_PATH=/path/to/libleptris.dylib bundle exec rspec` runs
against an arbitrary build (e.g. a libleptris checkout under test).

## Architecture

The C DOM is the single source of truth; Ruby objects are thin FFI
handles. One Ruby method = one FFI call wherever possible.

```
lib/leptris.rb                — Leptris::VERSION
lib/leptris/xml.rb            — autoload registry, error classes,
                                Leptris::XML.parse / parse_file
lib/leptris/xml/ffi.rb        — every public C declaration + seam
                                helpers (check_status, read_owned_string,
                                status_message)
lib/leptris/xml/document.rb   — the only C-memory owner (finalizer);
                                factories, PI accessors, exslt, last_error
lib/leptris/xml/node.rb       — Node.wrap: the ONLY wrapper constructor
                                (identity cache + type dispatch)
lib/leptris/xml/element.rb    — attributes via the v1.1.0 iteration
                                face; namespace/mutation surface
lib/leptris/xml/node_set.rb   — lazy XPath results; batch fetch via
                                get_nodes_ex
lib/leptris/xml/searchable.rb — xpath/css/at_*; namespace-bound path
lib/leptris/xml/xpath.rb      — compiled expressions (parse once,
                                eval many)
lib/leptris/xml/sax/          — callback SAX
lib/leptris/xml/pull.rb       — StAX-style pull parsing
lib/leptris/xml/iterparse.rb  — bounded-memory element iteration
lib/leptris/xml/serialization.rb — serialize/c14n (Document + Element
                                one-liners over this module)
lib/leptris/xml/c_string_array.rb — NULL-terminated char** adapter
lib/leptris/xml/css_to_xpath.rb   — minimal CSS translation
```

### Ownership and seams

- `Document` owns C memory (explicit `#free` or GC finalizer; wrapper
  cache is a strong Hash cleared on free). Every other class is a
  borrowed handle valid while its Document lives.
- All wrapper construction goes through `Node.wrap` — wrapper
  identity (`doc.root.equal?(doc.root)`) is guaranteed by the
  per-document cache.
- Status checks go through `FFI.check_status`; C `char*` returns go
  through `FFI.read_owned_string`; array wire format (both
  directions) goes through `CStringArray`. Never hand-roll these.
- The release workflow's publish loop is idempotent (already-published
  gems are skipped).

## Conventions

- Autoload only — no `require_relative` inside `lib/`.
- No `instance_variable_set`/`_get` across objects; no `respond_to?`
  type checks; specs use real documents, never doubles.
- New C surface: attach in `ffi.rb`, sugar where it earns its keep,
  specs against a locally built library, CHANGELOG, lockstep release.
- All changes via PRs; no AI attribution; `git add` explicit paths.

## Reference

- Domain vocabulary: CONTEXT.md. Settled decisions: docs/adr/ —
  check both before proposing refactors; they exist so reviews
  stop re-deriving settled questions.
- libleptris public headers (`src/include/leptris/*.h`) are the
  contract; when symbols change, bump lockstep and run
  `rake audit:symbols` (attached == exported on the vendored
  library; fails listing both directions of drift).
- Upstream issues worth tracking live at leptris/leptris.
