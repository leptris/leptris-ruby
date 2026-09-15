# 07 — Native read floor: shave the TypedData []/content dispatch (#204 ask 1)

Status: TODO

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
