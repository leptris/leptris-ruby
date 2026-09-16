# 35 — Document.parse default path as one C dispatch

Status: DONE (1.9.174.9)

The default parse path (no options, no recover — the adapter
default) is already allocation-free at the Ruby level (#187),
but still pays FFI marshaling, the wrap frames, the Freed and
Pointer constructions, and the handle attach across three Ruby
layers. One C face runs leptris_parse_string + the full document
wrapper (ivar-seeded) + lifetime handle and returns it; failure
raises the same ParseError shape via last_error read in C.

Gates: parse defaults identical (errors, readonly flag, root
access); the options/recover paths untouched; suite both modes.

## Outcome (1.9.174.9)

Native.parse_binding_document: leptris_parse_string + the full
ivar-seeded wrapper + lifetime handle in one dispatch (shared
build_binding_document helper); Document.parse's default path
(no options, no recover) routes through it, raising the same
ParseError shape via last_error on failure. Options/recover
paths untouched. Measured (load ~100, self-contained shape):
small parse 15.6µs -> 6.8µs (~2.3x).
