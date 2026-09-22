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
    module_function

    # Nokogiri::HTML shape: the default lane is html4 (byte-parity
    # with libxml2/Nokogiri::HTML), matching XML.parse_html's default.
    def parse(html)
      Leptris::XML.parse_html(html, mode: :html4)
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
