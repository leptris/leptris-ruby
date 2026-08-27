# frozen_string_literal: true

require "ffi"

module Leptris::XML::XSLT
  module_function

  def parse(stylesheet_xml)
    Stylesheet.parse(stylesheet_xml)
  end

  def parse_file(path)
    Stylesheet.parse_file(path)
  end

  # A compiled XSLT 1.0 stylesheet (libleptris 1.9.1): the stylesheet
  # parses ONCE into an immutable instruction forest — patterns to
  # XPath ASTs, selects through the compiled-XPath path — then applies
  # to any number of documents with no re-parsing.
  #
  #     style = Leptris::XML::XSLT.parse(<<~XSL)
  #       <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  #         <xsl:template match="/"><out><xsl:value-of select="count(//item)"/></out></xsl:template>
  #       </xsl:stylesheet>
  #     XSL
  #     style.apply_to(doc)      # => result Document (queryable tree)
  #     style.serialize(doc)     # => String (fragments and top-level
  #                              #    text nodes preserved)
  #
  class Stylesheet
    # GC-managed compiled handle.
    class Handle < ::FFI::AutoPointer
      def self.release(ptr)
        Leptris::XML::FFI.leptris_xslt_free(ptr)
      end
    end

    # Compile a stylesheet. Raises XPathError on a stylesheet syntax
    # error (detail on the thread-global last error).
    def self.parse(stylesheet_xml)
      raw = Leptris::XML::FFI.leptris_xslt_parse(
        stylesheet_xml.to_s, stylesheet_xml.to_s.bytesize)
      if raw.null?
        raise Leptris::XML::XPathError,
          "stylesheet parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    # Compile from a file. Resolves §2.7 embedded stylesheets
    # (xml-stylesheet PI with an href="#id" fragment) when the file's
    # root is not itself a stylesheet.
    def self.parse_file(path)
      raw = Leptris::XML::FFI.leptris_xslt_parse_file(path.to_s)
      if raw.null?
        raise Leptris::XML::XPathError,
          "stylesheet parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    def initialize(handle)
      @handle = handle
    end

    # Apply to +document+ (not modified) and return the result tree
    # as an owning Document — query it with xpath/css like any other.
    def apply_to(document)
      raw = Leptris::XML::FFI.leptris_xslt_apply(@handle, document.c_ptr)
      if raw.null?
        raise Leptris::XML::XPathError,
          "transform failed: #{document.last_error || Leptris::XML::FFI.leptris_last_error}"
      end
      Leptris::XML::Document.wrap(raw)
    end

    # Apply and serialize in one call — keeps top-level text nodes and
    # result fragments that the tree API would flatten.
    def serialize(document)
      str_ptr = Leptris::XML::FFI.leptris_xslt_apply_string(
        @handle, document.c_ptr)
      Leptris::XML::FFI.read_owned_string(str_ptr)
    end
  end
end
