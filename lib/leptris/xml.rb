# frozen_string_literal: true

# Eagerly load the FFI binding so the native library is resolved at
# require time, not lazily inside Document.parse. Without this, a
# ruby-platform gem install (which ships no binary) or any other
# resolution failure surfaces as a LoadError deep inside the first
# parse call — far from the `gem install` / `bundle install` that
# caused it. Resolving it here gives a clear, immediate error that
# names the platform variant the user must install instead.
# (Issue #49.)
begin
  require "leptris/xml/ffi"
rescue LoadError => e
  raise LoadError, <<~MSG
    Leptris could not load the native libleptris library.
    The ruby-platform gem is published as a fallback only and ships
    no binary; install the platform-specific variant for your system
    (e.g. `gem install leptris --platform=arm64-darwin`), or set
    LEPTRIS_LIB_PATH to a libleptris.{so,dylib,dll} file.
    (Underlying error: #{e.message})
  MSG
end

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
    autoload :Pull, "leptris/xml/pull"
    autoload :Iterparse, "leptris/xml/iterparse"

    # Nokogiri-style top-level entry points (Nokogiri::XML(...) /
    # Nokogiri::XML.parse). Delegates to Document.parse.
    def self.parse(xml_or_io, options: nil, readonly: false)
      Document.parse(xml_or_io, options: options, readonly: readonly)
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
