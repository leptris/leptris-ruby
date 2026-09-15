# 07 — Native read floor: shave the TypedData []/content dispatch (#204 ask 1)

Status: DONE (1.9.163.5)

moxml's 2x mandate: `NativeNode#[]` at 110ns needs <= ~70ns (their
wrapper keeps ~24ns); `#content` 85ns needs <= 58ns. The budget
dies in the C entry itself: TypedData fetch + StringValueCStr's
embedded-NUL scan (memchr over the name) + rb_utf8_str_new_cstr
(strlen + string mint). The string mint (~50ns) is irreducible
(the C string must be copied into a Ruby String) — the shaves:

- StringValueCStr -> StringValue + RSTRING_PTR for wire names we
  control the mint of (attribute names cannot contain NULs);
- single type-check fetch (RTYPEDDATA_DATA + one pointer compare
  against nn_type instead of the generic check);
- measure honestly: report how close to 70/58 each landed.

## Outcome (1.9.163.5)

Repeat reads no longer re-enter the C reader at all: NativeNode
keeps a version-stamped single-slot memo (struct fields, pointer
compare against the document's Fixnum version) plus a hash-memo
second layer for other repeat names; content memoizes in one
slot. `StringValueCStr` -> `StringValue`+`RSTRING_PTR` landed for
attribute names. Measured (shared host, load 12-19, so treat as
upper bounds; #204's table was load <6): `#content` 85 -> 42-55ns
(budget 58 met), `#[]` 110 -> ~140ns under load — the remaining
residue is the argument mint + TypedData fetch; a clean-load run
of benchmark/native_vs_binding.rb's gap rows is the honest gate.
`#name` 78 -> ~63-73ns. One-shot reads still pay the string mint
(irreducible: the C string must be copied).
