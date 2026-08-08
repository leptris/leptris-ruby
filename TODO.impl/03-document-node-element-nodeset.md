# TODO 3 — Document, Node, Element, NodeSet, Searchable implementation

## Goal

Implement the core Nokogiri-compatible Ruby classes backed by FFI
calls to libtaurus. Each Ruby method = one C function call.

## File layout

```
lib/taurus.rb                          # autoload + version
lib/taurus/xml.rb                      # XML module + parse entry points
lib/taurus/xml/ffi.rb                  # FFI declarations (TODO 2)
lib/taurus/xml/document.rb             # Document class
lib/taurus/xml/node.rb                 # Node base class
lib/taurus/xml/element.rb              # Element < Node
lib/taurus/xml/text.rb                 # Text < Node
lib/taurus/xml/comment.rb             # Comment < Node
lib/taurus/xml/cdata.rb               # CDATA < Node
lib/taurus/xml/processing_instruction.rb  # ProcessingInstruction < Node
lib/taurus/xml/attr.rb                 # Attr class
lib/taurus/xml/node_set.rb            # NodeSet class
lib/taurus/xml/searchable.rb          # Searchable mixin (xpath/css/search)
lib/taurus/xml/parse_options.rb       # ParseOptions class
```

## Autoload pattern

```ruby
# lib/taurus.rb
module Taurus
  autoload :XML, 'taurus/xml'
end

# lib/taurus/xml.rb
module Taurus
  module XML
    autoload :FFI,            'taurus/xml/ffi'
    autoload :Document,       'taurus/xml/document'
    autoload :Node,           'taurus/xml/node'
    autoload :Element,        'taurus/xml/element'
    autoload :Text,           'taurus/xml/text'
    autoload :Comment,        'taurus/xml/comment'
    autoload :CDATA,          'taurus/xml/cdata'
    autoload :ProcessingInstruction, 'taurus/xml/processing_instruction'
    autoload :Attr,           'taurus/xml/attr'
    autoload :NodeSet,        'taurus/xml/node_set'
    autoload :Searchable,     'taurus/xml/searchable'
    autoload :ParseOptions,   'taurus/xml/parse_options'

    def self.parse(string_or_io, options = nil)
      xml = string_or_io.respond_to?(:read) ? string_or_io.read : string_or_io
      status = ::FFI::MemoryPointer.new(:int)
      ptr = FFI.taurus_parse_string(xml, xml.bytesize, status)
      raise ParseError, "taurus_parse_string failed (status=#{status.read_int})" if ptr.nil? || ptr.null?
      Document.wrap(ptr)
    end
  end
end
```

## Document

```ruby
class Taurus::XML::Document < Taurus::XML::Node
  def self.wrap(c_ptr)
    doc = allocate
    doc.instance_variable_set(:@c_ptr, c_ptr)
    doc
  end

  def root
    ptr = FFI.taurus_document_root(@c_ptr)
    return nil if ptr.nil? || ptr.null?
    Taurus::XML::Element.wrap(ptr, self)
  end

  def xpath(expr)
    Taurus::XML::XPath.evaluate(@c_ptr, nil, expr)
  end

  def at_xpath(expr)
    result = xpath(expr)
    result.is_a?(NodeSet) ? result.first : result
  end

  def to_xml(options = {})
    opts = SerializeOptions.new
    opts[:indent] = options[:indent] || 0
    opts[:xml_declaration] = options[:no_decl] ? 0 : 1
    ptr = FFI.taurus_serialize_document(@c_ptr, opts.pointer)
    return '' if ptr.nil? || ptr.null?
    str = ptr.read_string
    FFI.taurus_free_string(ptr)
    str
  end

  def free
    return unless @c_ptr
    FFI.taurus_document_free(@c_ptr)
    @c_ptr = nil
  end
end
```

## Node (base class)

```ruby
class Taurus::XML::Node
  attr_reader :c_ptr, :document

  def initialize(c_ptr, document)
    @c_ptr = c_ptr
    @document = document
  end

  def self.wrap(c_ptr, document)
    type = FFI.taurus_node_get_type(c_ptr)
    case type
    when NODE_ELEMENT then Taurus::XML::Element.new(c_ptr, document)
    when NODE_TEXT    then Taurus::XML::Text.new(c_ptr, document)
    when NODE_COMMENT then Taurus::XML::Comment.new(c_ptr, document)
    when NODE_CDATA   then Taurus::XML::CDATA.new(c_ptr, document)
    when NODE_PI      then Taurus::XML::ProcessingInstruction.new(c_ptr, document)
    else new(c_ptr, document)
    end
  end

  def name
    raise NotImplementedError
  end

  def content
    raise NotImplementedError
  end

  def type
    FFI.taurus_node_get_type(@c_ptr)
  end

  def element?; type == NODE_ELEMENT; end
  def text?;    type == NODE_TEXT;    end
  def comment?; type == NODE_COMMENT; end
  def cdata?;   type == NODE_CDATA;   end
  def processing_instruction?; type == NODE_PI; end

  def next_sibling
    ptr = FFI.taurus_node_next_sibling(@c_ptr)
    return nil if ptr.null?
    Node.wrap(ptr, @document)
  end

  def previous_sibling
    ptr = FFI.taurus_node_previous_sibling(@c_ptr)
    return nil if ptr.null?
    Node.wrap(ptr, @document)
  end

  def parent
    ptr = FFI.taurus_element_parent(@c_ptr) # only works for elements
    return nil if ptr.null?
    Element.wrap(ptr, @document)
  end

  def children
    NodeSet.new(@document, self)
  end

  def child
    ptr = FFI.taurus_node_first_child(@c_ptr)
    return nil if ptr.null?
    Node.wrap(ptr, @document)
  end

  def traverse(&block)
    return enum_for(:traverse) unless block_given?
    block.call(self)
    children.each { |c| c.traverse(&block) }
  end

  include Searchable
end
```

## Element

```ruby
class Taurus::XML::Element < Taurus::XML::Node
  def name
    FFI.taurus_element_name(@c_ptr)
  end

  def name=(n)
    FFI.taurus_element_set_name(@c_ptr, n)
  end

  def content
    FFI.taurus_element_text(@c_ptr)
  end
  alias_method :text, :content

  def [](attr_name)
    FFI.taurus_element_attribute(@c_ptr, attr_name, nil)
  end

  def []=(attr_name, value)
    FFI.taurus_element_set_attribute(@c_ptr, attr_name, value.to_s)
  end

  def attributes
    # Walk the C attribute list, build a hash of Attr objects
    result = {}
    count = FFI.taurus_element_attribute_count(@c_ptr)
    # ... iterate attribute linked list ...
    result
  end

  def keys
    attributes.keys
  end

  def values
    attributes.values.map(&:value)
  end

  def first_element_child
    ptr = FFI.taurus_element_first_child_any(@c_ptr)
    return nil if ptr.null?
    Element.wrap(ptr, @document)
  end

  def add_child(node)
    FFI.taurus_element_append_child(@c_ptr, node.c_ptr)
    node
  end

  def add_class(names) ... end
  def remove_class(names = nil) ... end
  def classes
    (self['class'] || '').split
  end
end
```

## NodeSet

```ruby
class Taurus::XML::NodeSet
  include Enumerable
  include Searchable

  def initialize(document, result_ptr = nil)
    @document = document
    @result_ptr = result_ptr  # TaurusXPathResult pointer
  end

  def length
    return @cached_length if @cached_length
    @cached_length =
      @result_ptr ? FFI.taurus_xpath_result_count(@result_ptr) : 0
  end
  alias_method :size, :length

  def [](index)
    return nil if index < 0 || index >= length
    ptr = FFI.taurus_xpath_result_get(@result_ptr, index)
    return nil if ptr.null?
    Node.wrap(ptr, @document)
  end

  def first(n = nil)
    return self[0] if n.nil?
    NodeSet.new(@document).tap { |ns| n.times { |i| ns << self[i] } }
  end

  def last
    self[length - 1]
  end

  def each
    return enum_for(:each) unless block_given?
    length.times { |i| yield self[i] }
  end

  def empty?
    length == 0
  end

  def inner_text
    map(&:content).join
  end

  def to_xml
    map(&:to_xml).join
  end

  def free
    return unless @result_ptr
    FFI.taurus_xpath_result_free(@result_ptr)
    @result_ptr = nil
  end
end
```

## Searchable (mixin for xpath/css)

```ruby
module Taurus::XML::Searchable
  def xpath(*paths)
    expr = paths.join(' | ')
    result_ptr = FFI.taurus_xpath_eval(
      document.c_ptr,
      respond_to?(:c_ptr) ? c_ptr : nil,
      expr
    )
    return nil if result_ptr.null?

    result_type = FFI.taurus_xpath_result_type(result_ptr)
    case result_type
    when XPATH_NODESET
      NodeSet.new(@document, result_ptr)
    when XPATH_NUMBER
      n = FFI.taurus_xpath_result_number(result_ptr)
      FFI.taurus_xpath_result_free(result_ptr)
      n
    when XPATH_STRING
      s = FFI.taurus_xpath_result_string(result_ptr)
      FFI.taurus_xpath_result_free(result_ptr)
      s
    when XPATH_BOOLEAN
      b = FFI.taurus_xpath_result_boolean(result_ptr)
      FFI.taurus_xpath_result_free(result_ptr)
      b == 1
    end
  end

  def at_xpath(*paths)
    ns = xpath(*paths)
    ns.is_a?(NodeSet) ? ns.first : ns
  end

  def search(*args)
    expr = args.first.to_s
    if expr.start_with?('/') || expr.start_with?('//')
      xpath(expr)
    else
      css(expr)
    end
  end

  def at(*args)
    result = search(*args)
    result.is_a?(NodeSet) ? result.first : result
  end

  def css(*selectors)
    # Convert CSS to XPath (minimal converter)
    xpath_expr = CssToXPath.convert(selectors.join(', '))
    xpath(xpath_expr)
  end

  def at_css(*selectors)
    result = css(*selectors)
    result.is_a?(NodeSet) ? result.first : result
  end
end
```

## Implementation notes

- **No `require_relative`** anywhere. Use `autoload` defined in the
  immediate parent namespace's file (e.g., `lib/taurus/xml.rb`).
- **No `instance_variable_set`/`instance_variable_get`** on other
  objects. Use public accessor methods.
- **No `send`** to call private methods.
- **No `respond_to?`** for type checks. Use `is_a?`.
- Wrap C pointers in Ruby objects via `Node.wrap(ptr, doc)` which
  dispatches on the C node type.
- Node objects are lightweight: just a pointer + document reference.
  No caching of properties (each call goes through FFI).
- The document is the ONLY object that owns memory. All other objects
  are non-owning handles.
