# TODO 5 — Serialization, C14N, memory management, specs, CSS

## Serialization

Wrap `leptris_serialize_document` and `leptris_c14n_canonicalize`.

```ruby
# lib/leptris/xml/serialize_options.rb
class Leptris::XML::SerializeOptions < FFI::Struct
  layout \
    :indent,            :int,
    :xml_declaration,   :int,
    :no_empty_tags,     :int,
    :preserve_whitespace, :int
end

# Document#to_xml
def to_xml(options = {})
  opts = SerializeOptions.new
  opts[:indent]          = options[:indent] || 0
  opts[:xml_declaration] = options[:no_decl] ? 0 : 1
  opts[:no_empty_tags]   = options[:no_empty_tags] ? 1 : 0
  opts[:preserve_whitespace] = options[:preserve_whitespace] ? 1 : 0
  ptr = FFI.leptris_serialize_document(@c_ptr, opts.pointer)
  return '' if ptr.nil? || ptr.null?
  str = ptr.read_string
  FFI.leptris_free_string(ptr)
  str
end

# Node#to_xml (serialize just this subtree)
def to_xml(options = {})
  # No C API for single-node serialization yet. Use Document serialize
  # with a filter, or build the string manually. For v0.4.2, use the
  # document-level serialize and post-process. This is a known limitation.
  document.to_xml(options)
end

# Node#inner_html
def inner_html
  children.map { |c| c.to_xml }.join
end
```

## C14N (Canonical XML)

```ruby
# lib/leptris/xml/c14n.rb
module Leptris::XML
  C14N_1_0 = 0
  C14N_1_1 = 1
  C14N_EXCLUSIVE = 2

  class Document
    def canonicalize(mode = C14N_1_0, with_comments = false)
      ptr = FFI.leptris_c14n_canonicalize(@c_ptr, mode, with_comments ? 1 : 0)
      return '' if ptr.nil? || ptr.null?
      str = ptr.read_string
      FFI.leptris_free_string(ptr)
      str
    end
  end
end
```

## Memory management

### Ownership rules

| Ruby class  | Owns C memory? | Free function |
|-------------|----------------|---------------|
| Document    | YES            | `leptris_document_free` |
| Node/Element| NO (borrowed)  | none (freed by Document) |
| NodeSet     | YES (XPath result) | `leptris_xpath_result_free` |
| Attr        | NO (borrowed)  | none |

### Explicit free pattern

```ruby
doc = Leptris::XML.parse(xml)
begin
  # ... work with doc ...
ensure
  doc.free
end
```

### GC safety net

```ruby
class Leptris::XML::Document
  def self.wrap(ptr)
    obj = allocate
    obj.instance_variable_set(:@c_ptr, ptr)
    ObjectSpace.define_finalizer(obj, finalizer(ptr))
    obj
  end

  def self.finalizer(ptr)
    proc { FFI.leptris_document_free(ptr) if ptr && !ptr.null? }
  end

  def free
    return unless @c_ptr
    FFI.leptris_document_free(@c_ptr)
    @c_ptr = nil
    # The finalizer still holds the old pointer but Document#free
    # already freed it. Add a "freed" flag to detect double-free.
  end
end
```

**IMPORTANT**: The finalizer must capture the POINTER VALUE, not the
Document object (which would prevent GC). Use `FFI::Pointer` directly
in the finalizer closure.

### Prevent use-after-free

```ruby
class Leptris::XML::Node
  def c_ptr
    raise UseAfterFreeError, "document has been freed" unless @document.c_ptr
    @c_ptr
  end
end
```

## Specs

### Structure

```
spec/
  spec_helper.rb
  xml/
    parse_spec.rb
    document_spec.rb
    node_spec.rb
    element_spec.rb
    node_set_spec.rb
    xpath_spec.rb
    sax_spec.rb
    serialize_spec.rb
    c14n_spec.rb
    memory_spec.rb
  fixtures/
    basic.xml
    catalog.xml
    namespaces.xml
```

### Test against Nokogiri behavior

Where Nokogiri's behavior is well-defined, match it exactly. The
specs should test:

```ruby
# Parse
doc = Leptris::XML.parse('<root><child id="1">text</child></root>')
expect(doc.root.name).to eq('root')
expect(doc.root.children.first['id']).to eq('1')

# XPath
doc = Leptris::XML.parse('<lib><book/><book/></lib>')
expect(doc.xpath('count(//book)')).to eq(2.0)
expect(doc.xpath('//book').length).to eq(2)
expect(doc.at_xpath('//book')).to be_a(Leptris::XML::Element)

# Search
doc = Leptris::XML.parse('<root><a class="x"/><a class="y"/></root>')
expect(doc.search('a').length).to eq(2)
expect(doc.at('a')['class']).to eq('x')

# SAX
class Handler < Leptris::XML::SAX::Document
  attr_reader :elements
  def initialize; @elements = []; end
  def start_element(name, attrs = []); @elements << name; end
end

h = Handler.new
Leptris::XML::SAX::Parser.new(h).parse('<r><a/><b/></r>')
expect(h.elements).to eq(['r', 'a', 'b'])

# Serialize
doc = Leptris::XML.parse('<r/>')
expect(doc.to_xml).to match(/<r\/>/)

# C14N
expect(doc.canonicalize).to include('<r></r>')

# Memory
doc = Leptris::XML.parse('<r/>')
doc.free
expect { doc.root }.to raise_error(Leptris::XML::UseAfterFreeError)
```

### Conformance

Run Nokogiri's own test suite against the Leptris binding where
possible. Skip tests for features Leptris doesn't support (HTML5,
XSLT, RelaxNG, DTD validation beyond what libleptris provides).

## CSS-to-XPath converter (minimal)

```ruby
# lib/leptris/xml/css_to_xpath.rb
module Leptris::XML
  module CssToXPath
    def self.convert(rule)
      parts = rule.strip.split(/\s+/)
      xpath_parts = parts.map { |p| convert_part(p) }
      '//' + xpath_parts.join('/')
    end

    def self.convert_part(part)
      # tag → tag
      # .class → *[contains(concat(' ', @class,' '),' class ')]
      # #id → *[@id='id']
      # [attr] → *[@attr]
      # [attr=val] → *[@attr='val']
      # > child handled by split
      # :first-child → *[position()=1]
      # :last-child → *[position()=last()]
      return '*' if part == '*'

      if part.start_with?('.')
        cls = part[1..]
        "*[contains(concat(' ',normalize-space(@class),' '),' #{cls} ')]"
      elsif part.start_with?('#')
        id = part[1..]
        "*[@id='#{id}']"
      elsif match = part.match(/^(\w+)\[(\w+)='?([^'\]]+)'?\]$/i)
        "#{match[1]}[@#{match[2]}='#{match[3]}']"
      elsif match = part.match(/^(\w+)\[(\w+)\]$/i)
        "#{match[1]}[@#{match[2]}]"
      elsif match = part.match(/^(\w+):first-child$/i)
        "#{match[1]}[position()=1]"
      elsif match = part.match(/^(\w+):last-child$/i)
        "#{match[1]}[position()=last()]"
      else
        part  # pass through as tag name
      end
    end
  end
end
```

This is a minimal converter. For full CSS3 support, integrate the
`css_parser` gem or port Nokogiri's CSS parser.

## File layout summary

```
lib/leptris.rb
lib/leptris/xml.rb
lib/leptris/xml/
  ffi.rb
  document.rb
  node.rb
  element.rb
  text.rb
  comment.rb
  cdata.rb
  processing_instruction.rb
  attr.rb
  node_set.rb
  searchable.rb
  parse_options.rb
  serialize_options.rb
  css_to_xpath.rb
  sax.rb
  sax/
    parser.rb
    document.rb
```
