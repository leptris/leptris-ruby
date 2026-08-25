# ADR 0005: the eager FFI require runs after autoload registration

## Context
Issue #53: eager-loading ffi.rb from inside `module Leptris`
BEFORE `autoload :XML` was registered let ffi.rb's module opening
create Leptris::XML first; the registration was shadowed, xml.rb
never loaded, and the whole API was unreachable
(constants == [:FFI]).

## Decision
leptris.rb: register `autoload :XML` first, then the eager
`require "leptris/xml/ffi"` at top level — ffi.rb's module opening
triggers the autoload, landing FFI inside the real manifest module;
a downstream `require "leptris/xml"` is then a no-op. A subprocess
spec guards the cold path (the in-process suite cannot see it).

## Consequences
Any new eager require in leptris.rb must come after the autoload
block. Eager resolution at require time (issue #49) is unchanged.
