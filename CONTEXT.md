# Domain glossary

The vocabulary for talking about leptris-ruby. Architecture reviews
use these names; see docs/adr/ for settled decisions.

**The DOM** — the C tree built by libleptris. Single source of
truth: every Ruby object is a view over it, and one Ruby method is
one FFI call wherever possible.

**The seam** — `Leptris::XML::FFI`: every attach, every struct
layout, every buffer protocol, and the encoding policy (UTF-8 on
both faces: returns and callback params). ABI knowledge appears
nowhere else (document.rb's finalizer is ownership machinery;
CStringArray is the char** adapter).

**Ownership / the borrowed handle** — Document owns C memory
(explicit `#free` or GC finalizer); every other object (Node,
Element, Text, Comment, CDATA, PI, Attr, DocumentFragment, DocType)
is a handle borrowed for its document's lifetime. Mutations raise
ReadOnlyError on readonly documents; use of a handle after `#free`
raises UseAfterFreeError.

**Wrapper identity** — `Node.wrap` is the only wrapper constructor;
the per-document strong cache makes the same C node always yield the
same Ruby object (`doc.root.equal?(doc.root)`).

**The readonly contract** — `readonly: true` makes reads memoizable
because they cannot go stale; every read method follows the same
three-line pattern (return memo → compute → store memo). Mutations
are refused; detached factories still work.

**Lockstep** — the gem's major.minor tracks libleptris; a C release
is one PR (version.rb + Rakefile pin + CHANGELOG) then the release
workflow; ffi.rb mirrors the public header so the attached-vs-
exported audit (`nm -gU`) catches drift.

**The recover mode** — `recover: true` parses return an empty
document with the failure recorded on the thread-global last error
(+ position), instead of raising ParseError.
