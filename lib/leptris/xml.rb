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
    autoload :CStringArray, "leptris/xml/c_string_array"
    autoload :Serialization, "leptris/xml/serialization"
    autoload :SAX, "leptris/xml/sax"
    autoload :XPath, "leptris/xml/xpath"
    autoload :XSLT, "leptris/xml/xslt"
    autoload :Pull, "leptris/xml/pull"
    autoload :Iterparse, "leptris/xml/iterparse"

    # Nokogiri-style top-level entry points (Nokogiri::XML(...) /
    # Nokogiri::XML.parse). Delegates to Document.parse.
    def self.parse(xml_or_io, options: nil, readonly: false, recover: false)
      Document.parse(xml_or_io, options: options, readonly: readonly,
                     recover: recover)
    end

    def self.parse_file(path)
      Document.parse_file(path)
    end

    class Error < StandardError; end
    class ParseError < Error; end
    class ReadOnlyError < Error; end
    class XPathError < Error; end
    class UseAfterFreeError < Error; end
  end
end
