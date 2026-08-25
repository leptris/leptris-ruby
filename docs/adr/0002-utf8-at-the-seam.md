# ADR 0002: UTF-8 at the seam, both faces

## Context
The headers contract every C string as UTF-8, but FFI's implicit
string conversion returns ASCII-8BIT — on returns (2026-08-25,
release 1.9.3) and on FFI::Function callback params (2026-08-25,
1.9.4; only `characters` was corrected before).

## Decision
The encoding policy lives entirely in ffi.rb: the UTF8_RETURNS
wrap-list for called string-returning attaches, plus
read_owned_string, CStringArray.to_ruby, and the SAX adapter's
nil-safe utf8 for callback params. Mirror-only attachments stay
raw; they join the list when a call site appears.

## Consequences
Memoized readonly results can safely cache strings (they freeze as
UTF-8, the correct encoding, not BINARY). Non-ASCII content can no
longer leak BINARY into consumer code.
