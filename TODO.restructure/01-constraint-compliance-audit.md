# 01 — Constraint compliance audit (autoload / send / ivar / respond_to?)

Status: DONE

## Findings (2026-09-07 scan)

- `.send(` in lib: none.
- `instance_variable_set`/`_get` across objects: none.
  (`instance_variable_defined?(:@readonly_document)` in node.rb is
  a read-only memo predicate on self — not a set/get; reviewed and
  kept.)
- `require_relative` in lib/spec: none.
- `respond_to?` type checks — three real violations in lib + one
  in spec (fixed below).

## Sanctioned exceptions (documented, load-bearing)

- `leptris.rb` requires `leptris/version`: autoload cannot serve a
  bare constant (`Leptris::VERSION`), and the release workflow's
  bump step seds exactly this file.
- `leptris.rb` requires `leptris/xml/ffi` AFTER registering
  `autoload :XML`: eager native-library resolution (issue #49)
  with an ordering subtlety documented in the file (issue #53 —
  requiring earlier shadows the manifest module and hides the API).
- `require "ffi"` at the top of FFI-using files: external gem (the
  ban is on intra-library requires), needed because class bodies
  reference `::FFI::AutoPointer` at definition time.

## Fixes

- [x] `Document.parse`: `respond_to?(:read)` duck check → `is_a?(String)`
      branch (String passes through; readable objects read; anything
      else fails honestly with NoMethodError instead of silently
      parsing a garbage `to_s`).
- [x] `Iterparse.parse`: same replacement.
- [x] `SAX::Parser#parse`: lambda-guard `respond_to?(:read)` → explicit
      `when IO, StringIO, Pathname` branch (typed, MECE; previously
      anything readable dispatched, narrowing to the read-capable
      types the API documents).
- [x] `features_namespace_spec.rb`: dropped the `respond_to?` null-guard.
