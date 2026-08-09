# frozen_string_literal: true

module Taurus
  module XML
    autoload :FFI, "taurus/xml/ffi"
    autoload :Node, "taurus/xml/node"
    autoload :Element, "taurus/xml/element"
    autoload :Text, "taurus/xml/text"
    autoload :Comment, "taurus/xml/comment"
    autoload :CDATA, "taurus/xml/cdata"
    autoload :ProcessingInstruction, "taurus/xml/processing_instruction"
    autoload :Attr, "taurus/xml/attr"
    autoload :Namespace, "taurus/xml/namespace"
    autoload :Document, "taurus/xml/document"
    autoload :DocumentFragment, "taurus/xml/document_fragment"
    autoload :DocType, "taurus/xml/doc_type"
    autoload :NodeSet, "taurus/xml/node_set"
    autoload :Searchable, "taurus/xml/searchable"
    autoload :ParseOptions, "taurus/xml/parse_options"
    autoload :CssToXPath, "taurus/xml/css_to_xpath"
    autoload :SAX, "taurus/xml/sax"
    require "taurus/xml/c14n"  # module-level helper, eager load

    class Error < StandardError; end
    class ParseError < Error; end
    class XPathError < Error; end
    class UseAfterFreeError < Error; end
  end
end
