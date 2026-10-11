# frozen_string_literal: true

# The HTML facade (issue: "no HTML support in Ruby" — a discoverability
# gap, not a capability one). The engine has ONE DOM with multiple
# parser front-ends, so an HTML document IS a Leptris::XML::Document
# and every node/serializer/query face applies unchanged. What was
# missing was the shape porters scan for: a top-level HTML module
# mirroring the Nokogiri entry points.
#
#   Leptris::HTML(html)          # the html4 lane (Nokogiri::HTML parity)
#   Leptris::HTML5.parse(html)   # the WHATWG engine (html5lib zero reds)
#   Leptris::HTML4.parse(html)   # explicit html4 lane
#   Leptris::HTML5.create        # fresh document, <!DOCTYPE html> preset
#
# These are pure delegates — no parallel class hierarchy, no second
# wrapper cache; identity and the whole XML surface carry over.
# Construction flows through the same face as XML (create_element,
# add_child, root=, set_doctype) — `create` presets the doctype so a
# programmatically built document serializes with it; pair with
# `to_xml(no_decl: true)` for declaration-free HTML output (void
# elements serialize with the HTML5-legal trailing slash).
module Leptris
  module HTML
    # WHATWG fragment parsing with a context element (#1634 /
    # moxml#353). Composed over the WHATWG lane: the fragment runs
    # inside the context element's ancestor chain, so tree
    # construction lands in the right insertion mode (body context
    # keeps <title>/<meta> at fragment top level; table contexts
    # take the in-table rules). The wrapper document stays alive
    # for the fragment's lifetime - children address its pool.
    class Fragment
      # chains are the ancestors the parser opens before the
      # fragment: the innermost element carries the children
      TABLE_CHAINS = {
        table: %w[table],
        tbody: %w[table tbody],
        thead: %w[table thead],
        tfoot: %w[table tfoot],
        tr: %w[table tbody tr],
        td: %w[table tbody tr td],
        th: %w[table tbody tr th],
        caption: %w[table caption],
        colgroup: %w[table colgroup],
      }.freeze

      def initialize(document, chain)
        # The wrapper document always carries a body (explicit tag
        # or synthesis); table chains nest under it.
        @document = document
        el = first_element_named(document.root, "body")
        chain.each do |tag|
          break unless el
          el = first_element_named(el, tag)
        end
        @context = el
      end

      # The parsed top-level nodes (text, elements, comments) in
      # tree order - the fragment's children, Nokogiri's
      # DocumentFragment#children shape.
      def children
        @context ? @context.children.to_a : []
      end

      def each(&block)
        children.each(&block)
      end

      include Enumerable

      def size
        children.size
      end

      def empty?
        children.empty?
      end

      # The fragment serialized as its children joined (HTML
      # method per node; text verbatim).
      def to_html
        children.map do |c|
          c.is_a?(Leptris::XML::Text) ? c.content : c.to_html
        end.join
      end

      private

      def first_element_named(parent, name)
        parent.children.find do |c|
          c.is_a?(Leptris::XML::Element) && c.name == name
        end
      end
    end

    module_function

    # Nokogiri::HTML shape: the default lane is html4 (byte-parity
    # with libxml2/Nokogiri::HTML), matching XML.parse_html's default.
    def parse(html)
      Leptris::XML.parse_html(html, mode: :html4)
    end

    # WHATWG fragment parse (body context by default; the table
    # contexts wrap their ancestor chain). Matches
    # Nokogiri::HTML5.fragment semantics on the head-sweep and
    # foster-parenting divergence set (verified against the
    # html5lib trees).
    def parse_fragment(html, context: :body)
      chain = context == :body ? ["body"] : Fragment::TABLE_CHAINS.fetch(context) do
        raise ArgumentError,
              "context must be :body or a table context " \
              "(#{(Fragment::TABLE_CHAINS.keys + [:body]).join(', ')}), " \
              "got #{context.inspect}"
      end
      prefix = "<body>#{chain.map { |t| "<#{t}>" }.join}"
      suffix = "#{chain.reverse.map { |t| "</#{t}>" }.join}</body>"
      wrapped = "#{prefix}#{html}#{suffix}"
      Fragment.new(Leptris::HTML5.parse(wrapped),
                   chain.first == "body" ? chain.drop(1) : chain)
    end

    # Fresh document with the HTML 4.01 Transitional doctype preset
    # (Nokogiri::HTML::Builder's .doc carries the same). Pass
    # +doctype: nil+ for a bare document.
    def create(doctype: :transitional, skeleton: true)
      create_document(doctype, skeleton: skeleton)
    end

    def create_document(doctype, skeleton: true)
      doc = Leptris::XML::Document.create
      case doctype
      when :html5, true
        doc.set_doctype("html")
      when :transitional
        doc.set_doctype(
          "HTML",
          public_id: "-//W3C//DTD HTML 4.01 Transitional//EN",
          system_id: "http://www.w3.org/TR/html4/loose.dtd")
      when nil, false then nil
      else raise ArgumentError,
        "doctype must be :html5, :transitional, nil, or false, got #{doctype.inspect}"
      end
      return doc unless skeleton
      html = doc.create_element("html")
      head = doc.create_element("head")
      body = doc.create_element("body")
      html.add_child(head)
      html.add_child(body)
      doc.root = html
      doc
    end
  end

  module HTML4
    module_function

    def parse(html)
      Leptris::XML.parse_html(html, mode: :html4)
    end

    def create(doctype: :transitional, skeleton: true)
      Leptris::HTML.create_document(doctype, skeleton: skeleton)
    end
  end

  module HTML5
    module_function

    # The conformant WHATWG engine: full implied-head set, foster
    # parenting, adoption agency, template, RCDATA/rawtext (see
    # spec/xml/html_whatwg_full_spec.rb).
    def parse(html)
      Leptris::XML.parse_html(html, mode: :whatwg)
    end

    # Fresh document with the HTML5 doctype (`<!DOCTYPE html>`)
    # preset; pass +doctype: nil+ for a bare document.
    def create(doctype: :html5, skeleton: true)
      Leptris::HTML.create_document(doctype, skeleton: skeleton)
    end
  end
end
