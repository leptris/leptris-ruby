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
    autoload :EvaluationContext, "leptris/xml/evaluation_context"
    autoload :IterationScope, "leptris/xml/iteration_scope"
    autoload :ResultText, "leptris/xml/result_text"
    autoload :ResultAttr, "leptris/xml/result_attr"
    autoload :XSLT, "leptris/xml/xslt"
    autoload :XQuery, "leptris/xml/xquery"
    autoload :RelaxNG, "leptris/xml/relaxng"
    autoload :Schematron, "leptris/xml/schematron"
    autoload :Pull, "leptris/xml/pull"
    autoload :Iterparse, "leptris/xml/iterparse"

    # Nokogiri-style top-level entry points (Nokogiri::XML(...) /
    # Nokogiri::XML.parse). Delegates to Document.parse.
    def self.parse(xml_or_io, options: nil, readonly: false, recover: false)
      Document.parse(xml_or_io, options: options, readonly: readonly,
                     recover: recover)
    end

    # Does +string+ contain a named entity reference that is not
    # one of the five predefined XML entities (nor numeric)? One C
    # pass (libleptris 1.9.62) — downstream adapters use it to skip
    # whole-buffer rewrites when a document is already clean.
    def self.buffer_has_nonstandard_entity?(string)
      string = string.to_s
      Leptris::XML::FFI.leptris_str_has_nonstandard_entity(
        string, string.bytesize) != 0
    end

    # Tolerant HTML parse into a standard Document (libleptris
    # 1.9.75): implied end tags, void elements, raw-text script and
    # style, lowercased names, minimized/unquoted attributes, and
    # the HTML named entities. html/head/body are synthesized; no
    # implied tbody. Malformed input degrades to text rather than
    # raising; only an entirely empty result is an error.
    #
    # MODES (libleptris 1.9.104, #659): :html4 (the default) pins
    # the libxml2/Nokogiri compatibility shape — leading
    # script/style stay in <body>, title/meta/link/base still lift
    # — so byte-parity with Nokogiri::HTML holds. :whatwg selects
    # the conformant engine: the full implied-<head> set
    # (script/style/noscript/template/... lift) and foster
    # parenting (1.9.105) — html5lib corpus 294/1555 vs Nokogiri's
    # 372; the shapes genuinely differ by spec.
    def self.parse_html(html, mode: :html4)
      html = html.to_s
      entry =
        case mode
        when :html4 then Leptris::XML::FFI.method(:leptris_parse_html4_string)
        when :whatwg then Leptris::XML::FFI.method(:leptris_parse_html_string)
        else
          raise ArgumentError,
            "mode must be :html4 or :whatwg, got #{mode.inspect}"
        end
      raw = entry.call(html, html.bytesize, nil)
      if raw.null?
        raise Leptris::XML::ParseError,
          "HTML parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      Leptris::XML::Document.wrap(raw)
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
