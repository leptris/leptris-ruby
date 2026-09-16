# 36 — Status raises in C + encoding on the serializer faces

Status: DONE (1.9.174.10)

Every C mutation face returns INT2FIX(st) for a Ruby check_status
dispatch (~30ns per mutation, plus a whole class of
"forgot-to-check" bug the compiler cannot catch). With
leptris_status_string and leptris_last_error both dlsym'd, the
faces raise Leptris::XML::Error in C with the exact
status_message format ("base" or "base (detail)") — call sites
shrink to the bare face call.

The ext serializer faces skip the encoding-tagged shape entirely
(to_xml(encoding: ...) still builds the options struct through
FFI): the faces gain an encoding VALUE (nil -> NULL, the Ruby
string's bytes stay valid across the synchronous engine call).

Gates: every mutation's failure message byte-identical to
check_status; encoding-tagged to_xml output identical to the FFI
path (declaration, no anchor lifetime issues); suite both modes.

## Outcome (1.9.174.10)

All seven mutation faces raise Leptris::XML::Error in C with the
exact status_message format (status_string + optional
" (last_error)") — the Ruby check_status dispatch disappears from
every fast mutation. TRAP FOUND: the faces' success return became
Qnil, colliding with the lift-needed marker — every fast mutation
fell through to the slow path and re-applied (order-corrupting
for inserts; the v180 bottom-up spec caught it). Success now
returns Qtrue. The serializer faces take an encoding VALUE (nil
-> NULL; the Ruby string's bytes live across the synchronous
call), and to_xml(encoding:) rides the ext face instead of the
options-struct FFI path.
