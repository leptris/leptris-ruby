# TODO 1 — Architecture: C-backed Nokogiri-compatible Ruby binding

## Goal

Rewrite `taurus-ruby` to be a **thin FFI wrapper** around libtaurus v0.4.2,
exposing a **Nokogiri-compatible API**. The C DOM is the single source of
truth — no Ruby-side tree copy.

## Current state (problem)

The existing `taurus-ruby` has:
- A **pure-Ruby** XML tree model (Document < Element, Node, NodeSet)
- A FFI bridge that does a **one-shot copy** from C to Ruby on parse
- A **pure-Ruby XPath engine** (lexer, parser, compiler, VM in Ruby)

This defeats libtaurus's performance: the C library's optimized bytecode
VM + element index are never used. XPath goes through the slow Ruby engine.

## Target architecture

```
User Ruby code
    ↓
Taurus::XML::Document / Node / NodeSet  (thin Ruby wrappers)
    ↓ FFI
libtaurus v0.4.2  (C99: DOM, XPath bytecode VM, element index)
```

Key principles:
- **Every Ruby method is a single FFI call** to the C library.
- **No Ruby-side tree copy.** The C DOM is the truth; Ruby objects are
  handles (wrapping opaque pointers).
- **XPath goes through C.** `doc.xpath('//book')` calls
  `taurus_xpath_eval` directly. No Ruby XPath engine.
- **SAX goes through C.** `Taurus::XML::SAX::Parser` wraps
  `taurus_sax_parse` with Ruby callback dispatch.

## Module structure (Nokogiri-compatible)

```ruby
module Taurus
  module XML
    # Top-level parse entry points
    def self.parse(string_or_io)  →  Document
    def self.parse_options         →  ParseOptions

    class Document < Node
      def root                    →  Element (or nil)
      def create_element(name)    →  Element
      def create_text_node(text)  →  Text
      def to_xml(options)         →  String
      def xpath(expr)             →  NodeSet | Float | String | Boolean
      def at_xpath(expr)          →  Node (or nil)
      def search(expr)            →  NodeSet
      def canonicalize(...)       →  String
      def free                    →  void  (explicit)
    end

    class Node
      include Searchable

      def name                    →  String
      def content / text          →  String
      def [](attr_name)           →  String (or nil)
      def []=(attr_name, value)
      def attributes              →  Hash {String => Attr}
      def children                →  NodeSet
      def child                   →  Node (or nil)
      def first_element_child     →  Element (or nil)
      def last_element_child      →  Element (or nil)
      def next_sibling            →  Node (or nil)
      def previous_sibling        →  Node (or nil)
      def parent                  →  Node (or nil)
      def document                →  Document
      def type                    →  Integer (element/text/comment/cdata/pi)
      def element?                →  Boolean
      def text?                   →  Boolean
      def comment?                →  Boolean
      def cdata?                  →  Boolean
      def processing_instruction? →  Boolean
      def add_child(node)         →  Node
      def add_next_sibling(node)  →  Node
      def add_previous_sibling(node) → Node
      def remove                  →  Node
      def replace(node)           →  Node
      def to_xml(options)         →  String
      def inner_html              →  String
      def traverse(&block)
    end

    class Element < Node
      def add_class(name)
      def remove_class(name)
      def classes                 →  Array<String>
    end

    class Text < Node; end
    class Comment < Node; end
    class CDATA < Node; end
    class ProcessingInstruction < Node; end
    class Attr
      def name                    →  String
      def value                   →  String
      def value=(val)
      def parent                  →  Element
      def remove
    end

    class NodeSet
      include Enumerable
      include Searchable

      def length / size           →  Integer
      def first(n)                →  Node | NodeSet
      def last                    →  Node
      def [](index)               →  Node
      def each(&block)
      def empty?                  →  Boolean
      def xpath(expr)             →  NodeSet
      def search(expr)            →  NodeSet
      def to_xml                  →  String
      def inner_text              →  String
    end

    module Searchable
      def xpath(*paths)           →  NodeSet | Float | String | Boolean
      def at_xpath(*paths)        →  Node (or nil)
      def css(*selectors)         →  NodeSet (converts CSS to XPath)
      def at_css(*selectors)      →  Node (or nil)
      def search(*args)           →  NodeSet (auto-detect CSS/XPath)
      def at(*args)               →  Node (or nil)
    end

    class ParseOptions
      DEFAULT_XML = ...
      RECOVER = ...
      NOERROR = ...
      NOWARNING = ...
      NOCDATA = ...
      STRICT = ...
    end

    module SAX
      class Parser
        def initialize(handler = DocHandler.new)
        def parse(io_or_string)
      end

      class Document
        def start_element(name, attrs = [])
        def end_element(name)
        def characters(string)
        def start_document
        def end_document
        def comment(string)
        def cdata(string)
        def processing_instruction(name, content)
        def error(message, line, column)
      end
    end
  end
end
```

## Memory model

- **Document** owns the C document pool. `Taurus::XML::Document.new`
  calls `taurus_parse_string` → returns a `TaurusDocument` pointer.
  `Document#free` calls `taurus_document_free`. Auto-free via
  `ObjectSpace.define_finalizer` as a safety net (but callers should
  call `#free` explicitly for predictable lifecycle).
- **Node / Element / Text etc.** are **non-owning handles** wrapping
  a C pointer. The pointer is valid as long as the parent Document
  is alive. Freeing a Node just drops the Ruby wrapper; the C node
  lives until `Document#free`.
- **NodeSet** wraps a `TaurusXPathResult` pointer from
  `taurus_xpath_eval`. Freeing a NodeSet calls
  `taurus_xpath_result_free`.
- **Attr** wraps a C attribute pointer (owned by the parent element's
  pool). Non-owning.

## CSS support

Nokogiri supports CSS selectors via `css()` and `at_css()`. Taurus
doesn't have a CSS engine in C, so CSS-to-XPath conversion must be
done in Ruby. Options:
1. Use the `css_parser` gem (depends on `racc`).
2. Write a minimal CSS-to-XPath converter in pure Ruby.

For v0.4.2 compatibility, option 2 (minimal converter) is recommended.
Nokogiri's CSS selector support is comprehensive but the common subset
is small: `tag`, `.class`, `#id`, `> child`, `descendant`,
`[attr]`, `[attr=value]`, `:first-child`, `:last-child`, `:not(...)`.

## Dependencies

```ruby
# taurus.gemspec
spec.add_dependency 'ffi', '~> 1.16'
```

No other runtime dependencies. No C extension compilation needed —
just FFI to the pre-built libtaurus shared library.

## Reference material

- Nokogiri source: `~/src/external/nokogiri/`
  - `lib/nokogiri/xml/node.rb` — 77 public methods
  - `lib/nokogiri/xml/node_set.rb` — 31 public methods
  - `lib/nokogiri/xml/document.rb` — 22 public methods
  - `lib/nokogiri/xml/searchable.rb` — xpath/css/search module
- libtaurus public headers: `src/include/taurus/`
  - `types.h` — opaque handle typedefs
  - `dom/document.h`, `dom/element.h`, `dom/serialize.h`
  - `xpath/xpath.h` — XPath eval API
  - `sax/sax.h` — SAX parser API
- libtaurus v0.4.2: tag `v0.4.2` on `github.com:lutaml/taurus`
