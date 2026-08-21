# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`leptris-ruby` is a Ruby gem that wraps the native C library `libleptris` (built via CMake) via the `ffi` gem. It exposes an XML parser with complete XPath 1.0 support and a CLI. Target users want Nokogiri-like ergonomics with native speed.

- Native dep: `libleptris` shared library, built by `ext/leptris/extconf.rb` (CMake) and copied to `lib/libleptris.{dylib,so,dll}`.
- Ruby entry point: `lib/leptris.rb` (uses `require_relative` — see "Conventions" below).
- CLI: `bin/leptris` (Thor-based), defined in `lib/leptris/cli.rb`.

## Commands

```bash
# Build the C library and install it into lib/ for FFI to load
bundle exec rake compile            # runs ext/leptris/extconf.rb (CMake)

# Run the full test suite (builds first)
bundle exec rake test               # = spec, depends on :compile

# Run RSpec directly (skips build dependency)
bundle exec rspec                   # full suite
bundle exec rspec spec/leptris/document_spec.rb    # one file
bundle exec rspec spec/leptris/document_spec.rb:42 # one example by line

# Lint
bundle exec rubocop

# Clean build artifacts (lib/libleptris.*, ext/leptris/build, Makefile, tmp, pkg)
bundle exec rake clean
```

CI (`.github/workflows/test.yml`) runs `bundle exec rspec` + `bundle exec rubocop` on Ubuntu + macOS across Ruby 3.0–3.3.

## Architecture: current state (v1.1.0)

```
User Ruby code
    ↓
Leptris.parse / Leptris.parse_file                  (lib/leptris.rb)
    ↓ FFI call (leptris_parse) — one-shot tree copy
C document → FFI::Bridge.document_from_ptr        (lib/leptris/ffi/bridge.rb)
    ↓ recursive hydration
Ruby Document → Element → Node → NodeSet          (lib/leptris/{document,element,node,node_set}.rb)
```

Key directories:

- `lib/leptris.rb` — top-level module, `parse`, `parse_file`, `xpath_evaluate`, error classes (`ParseError`, `XPathError`, `EvaluationError`).
- `lib/leptris/ffi/` — FFI plumbing: `library.rb` (bindings), `types.rb` (constants), `memory.rb` (AutoPointer wrappers), `errors.rb` (thread-local error check), `bridge.rb` (C ptr → Ruby object).
- `lib/leptris/{document,element,node,node_set}.rb` — pure-Ruby tree model (full hydration on parse).
- `lib/leptris/xpath/` — pure-Ruby XPath engine (lexer, parser, compiler, VM). XPath DOES NOT go through C currently; `lib/leptris.rb#xpath_evaluate` calls `FFI.leptris_xpath_eval` only as a wrapper, but the result materialization in `FFI::Bridge` recursively re-walks via the Ruby tree.
- `lib/leptris/adapter*` — third-party format adapters.
- `spec/leptris/` — 250+ RSpec examples covering parser, XPath, namespaces, errors, ox-compatibility.
- `ext/leptris/` — CMake-based build of `libleptris` (sources come from the separate `leptris/leptris` repo at build time).

## Architecture: planned rewrite (see `TODO.impl/`)

The five files under `TODO.impl/` describe a planned rewrite that has NOT been implemented yet. Read them before touching the Ruby/COM layer. Summary:

1. **`01-architecture.md`** — Rewrite `leptris-ruby` as a **thin FFI wrapper** around libleptris v0.4.2 with a **Nokogiri-compatible API**. Current code does a one-shot C→Ruby tree copy and runs XPath in Ruby; planned code keeps the C DOM as the single source of truth (Ruby objects = handles wrapping opaque pointers), so every Ruby method = one FFI call and XPath/SAX go through the C engine.

2. **`02-ffi-declarations.md`** — Complete FFI attachment: every public function in libleptris v0.4.2 (document lifecycle, node access, element queries/mutation, creation, text/comment/CDATA/PI access, XPath + variable set, SAX, serialization, `leptris_free_string`). Opaque typedefs: `document`, `element`, `node_ref`, `xpath_result`, `sax_parser`, `attribute`. Structs: `SAXHandler`, `SerializeOptions`. Constants for status codes, node types, XPath result types.

3. **`03-document-node-element-nodeset.md`** — Target file layout:
   ```
   lib/leptris.rb
   lib/leptris/xml.rb
   lib/leptris/xml/{ffi,document,node,element,text,comment,cdata,
                   processing_instruction,attr,node_set,searchable,
                   parse_options}.rb
   ```
   `Node.wrap(ptr, doc)` dispatches on the C node type. Document is the only memory-owning object; Node/Element/Text/Comment/CDATA/PI/Attr are non-owning handles valid until `Document#free`.

4. **`04-sax-parser.md`** — `Leptris::XML::SAX::{Parser, Document}` wrapping `leptris_sax_parse` / `leptris_sax_parser_feed`. FFI::Function callbacks for each event; `start_element` walks the NULL-terminated `const char**` attribute array. Streaming via incremental `feed`.

5. **`05-serialize-c14n-memory-specs-css.md`** — `SerializeOptions` struct for `leptris_serialize_document`; `Document#canonicalize` (modes `C14N_1_0`, `C14N_1_1`, `C14N_EXCLUSIVE`); `UseAfterFreeError` guard; minimal CSS-to-XPath converter (`.class`, `#id`, `[attr]`, `[attr=val]`, `:first-child`, `:last-child`); spec layout under `spec/xml/{parse,document,node,element,node_set,xpath,sax,serialize,c14n,memory}_spec.rb`.

### Memory ownership rules (planned)

| Ruby class | Owns C memory? | Free function |
|---|---|---|
| `Document` | YES | `leptris_document_free` |
| `Node`/`Element`/text/CDATA/PI/Attr | NO (borrowed) | freed transitively by Document |
| `NodeSet` (XPath result) | YES | `leptris_xpath_result_free` |
| SAX handler closures | callback lifetime | `leptris_sax_parser_free` |

GC safety net: `ObjectSpace.define_finalizer` capturing the **raw pointer value**, not the Ruby wrapper. Finalizers must not double-free after explicit `#free`.

## Reference material

- Nokogiri source (`~/src/external/nokogiri/`) — `lib/nokogiri/xml/{node,node_set,document,searchable}.rb` are the API shape targets.
- libleptris public headers (`src/include/leptris/{types,leptris}.h`, `src/include/leptris/{dom,xpath,sax}/*.h`) — the single source of truth for FFI declarations. Target tag: `v0.4.2`.
- `docs/FFI_ARCHITECTURE.md` — describes the v0.5.0 FFI design (AutoPointer, two-pointer strategy for XPath). The planned rewrite supersedes some of this (no recursive hydration, no two-pointer — the Document pointer alone suffices because Node objects stay as C handles).
- `docs/BUILD.md` — CMake build reference for libleptris itself.

## Conventions (project-specific)

- **Autoload, not require_relative.** TODO 3 is explicit: `lib/leptris.rb` → `autoload :XML, 'leptris/xml'`; `lib/leptris/xml.rb` → `autoload :Document, 'leptris/xml/document'`. Autoload entries live in the **immediate parent namespace's file** (create that file if missing). The current `lib/leptris.rb` uses `require_relative` — when implementing TODO 3, do not retrofit require_relative into the new layout.
- **No `instance_variable_set`/`_get` cross-object.** TODO 3 is explicit. The current `lib/leptris.rb` and `lib/leptris/ffi/bridge.rb` use `instance_variable_get(:@_c_ptr)` heavily — that pattern is debt to migrate, not a model to copy. In the rewrite, expose `c_ptr`/`document` as public `attr_reader`s and access via those.
- **No `respond_to?` type checks.** Use `is_a?`. The current `lib/leptris.rb#xpath_evaluate` checks `context_node != doc` to disambiguate — fine. Don't add `respond_to?(:c_ptr)` style checks.
- **No doubles in specs.** The existing `spec/leptris/` specs use real model instances (XML strings → `Leptris.parse` → real `Document`/`Element`/`NodeSet`). Keep it that way.
- **Forward compatibility:** Keep `Leptris.parse` / `Leptris.parse_file` as the existing top-level API during the rewrite. The new `Leptris::XML.parse` may coexist.