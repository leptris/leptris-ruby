# frozen_string_literal: true

module Leptris::XML
  # Markup-accumulating subtree builder (the #374 lever-2 face):
  # `build` blocks append markup into a buffer with proper escaping
  # and flush ONCE at block end — one fragment-parse crossing for
  # the whole subtree, no per-node Ruby→C crossings. The object
  # faces (create_element/add_child) remain the tool for
  # interactive, node-in-hand construction; the builder is for the
  # programmatic fresh-document / wholesale-subtree shape.
  #
  #   doc.build do |b|
  #     b.catalog(id: "c") do
  #       b.item(id: 1) do
  #         b.name "Item 1"
  #         b.price "1.99"
  #       end
  #     end
  #   end
  #
  # Values evaluate as plain strings — text and attribute values
  # are escaped (& < > and " in attributes). Reserved method names
  # are reachable through #element; #text, #cdata and #comment add
  # those node kinds; #raw splices trusted markup verbatim.
  class Builder
    NAME_RE = /\A[a-zA-Z_][\w.-]*\z/.freeze

    attr_reader :markup

    def initialize
      @markup = +""
      @stack = []
    end

    def text(content)
      @markup << escape_text(content.to_s)
      nil
    end

    def cdata(content)
      body = content.to_s
      raise ArgumentError, %(CDATA cannot contain ']]>') if body.include?("]]>")

      @markup << "<![CDATA[" << body << "]]>"
      nil
    end

    def comment(content)
      @markup << "<!-- " << content.to_s << " -->"
      nil
    end

    def raw(trusted_markup)
      @markup << trusted_markup.to_s
      nil
    end

    def element(name, text_or_attrs = nil, attrs = nil, &block)
      attrs = text_or_attrs if text_or_attrs.is_a?(Hash)
      attrs ||= {}
      open_tag(name, attrs)
      if block
        yield self
      elsif text_or_attrs.is_a?(String) || text_or_attrs.is_a?(Numeric)
        @markup << escape_text(text_or_attrs.to_s)
      end
      close_tag(name)
      nil
    end

    def method_missing(name, *args, &block)
      element(name.to_s, *args, &block)
    end

    def respond_to_missing?(name, include_private = false)
      NAME_RE.match?(name.to_s) || super
    end

    # Escapes, open/close, and the name check, exposed for the
    # document/element flush faces.
    def open_tag(name, attrs)
      check_name(name)
      @markup << "<" << name
      (attrs || {}).each do |k, v|
        check_name(k.to_s)
        @markup << " " << k.to_s << "=\"" << escape_attr(v.to_s) << "\""
      end
      @markup << ">"
    end

    def close_tag(name)
      check_name(name)
      @markup << "</" << name << ">"
    end

    def check_name(name)
      unless NAME_RE.match?(name)
        raise ArgumentError,
              "builder element names must match #{NAME_RE.inspect} " \
              "(got #{name.inspect})"
      end
    end

    ESCAPE_TEXT = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;" }.freeze
    ESCAPE_ATTR = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;",
                    '"' => "&quot;" }.freeze
    private_constant :ESCAPE_TEXT, :ESCAPE_ATTR

    # Single-pass: three/four chained gsubs mint a temporary string
    # per pattern — on builder-shaped workloads (10k+ values per
    # flush) that dominated the accumulation.
    def escape_text(s)
      s.gsub(/[&<>]/, ESCAPE_TEXT)
    end

    def escape_attr(s)
      s.gsub(/[&<>"]/, ESCAPE_ATTR)
    end
  end
end
