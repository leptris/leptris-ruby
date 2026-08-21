# frozen_string_literal: true

module Leptris
  module XML
    autoload :FFI, "leptris/xml/ffi"
    autoload :Node, "leptris/xml/node"
    autoload :Element, "leptris/xml/element"
    autoload :Text, "leptris/xml/text"
    autoload :Comment, "leptris/xml/comment"
    autoload :CDATA, "leptris/xml/cdata"
    autoload :ProcessingInstruction, "leptris/xml/processing_instruction"
    autoload :Attr, "leptris/xml/attr"
    autoload :Namespace, "leptris/xml/namespace"
    autoload :Document, "leptris/xml/document"
    autoload :DocumentFragment, "leptris/xml/document_fragment"
    autoload :DocType, "leptris/xml/doc_type"
    autoload :NodeSet, "leptris/xml/node_set"
    autoload :Searchable, "leptris/xml/searchable"
    autoload :ParseOptions, "leptris/xml/parse_options"
    autoload :CssToXPath, "leptris/xml/css_to_xpath"
    autoload :SAX, "leptris/xml/sax"
    require "leptris/xml/c14n"  # module-level helper, eager load

    # Nokogiri-style top-level entry points (Nokogiri::XML(...) /
    # Nokogiri::XML.parse). Delegates to Document.parse.
    def self.parse(xml_or_io)
      Document.parse(xml_or_io)
    end

    def self.parse_file(path)
      Document.parse_file(path)
    end

    class Error < StandardError; end
    class ParseError < Error; end
    class XPathError < Error; end
    class UseAfterFreeError < Error; end
  end
end
