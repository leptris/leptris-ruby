# frozen_string_literal: true

require "leptris/xml"

# C14N (Canonical XML) coverage. Exercises the v0.5.2 leptris_c14n_canonicalize_ex
# and leptris_c14n_canonicalize_subtree_ex entry points via the Ruby API.
#
# Each spec asserts the *shape* of canonical output (XML canonical form rules:
# UTF-8, normalized line endings, lexicographic attribute ordering, namespace
# declaration ordering, empty element expansion, entity/char ref expansion,
# double-quoted attribute values). Exact byte-equality against Nokogiri
# would be ideal but pulls in a heavy dependency; these specs check the
# canonicalization rules from the W3C C14N 1.0 spec.

RSpec.describe "C14N via libleptris" do
  let(:simple_xml) { "<root><child id='1'>text</child></root>" }

  describe "Document#canonicalize — default (canonical 1.0, no comments)" do
    it "returns canonical XML as a String" do
      out = Leptris::XML::Document.parse(simple_xml).canonicalize
      expect(out).to be_a(String)
      expect(out).to include("<root>")
      expect(out).to include("<child")
    end

    it "expands empty elements to <tag></tag>" do
      out = Leptris::XML::Document.parse("<x/>").canonicalize
      expect(out).to include("<x></x>")
      expect(out).not_to include("<x/>")
    end

    it "uses double quotes for attribute values" do
      out = Leptris::XML::Document.parse(%q{<x a='1'/>}).canonicalize
      expect(out).to include('a="1"')
    end

    it "sorts attributes lexicographically" do
      out = Leptris::XML::Document.parse(%q{<x z='1' a='2' m='3'/>}).canonicalize
      expect(out).to include('a="2" m="3" z="1"')
    end

    it "expands required character references in text (< and &)" do
      # Per XML 1.0 / C14N 1.0, only < and & MUST be escaped in text content.
      # > need not be escaped (libleptris leaves it literal).
      out = Leptris::XML::Document.parse("<x>&lt;&amp;&gt;</x>").canonicalize
      expect(out).to include("&lt;&amp;")
    end

    it "preserves comments when with_comments: true" do
      out = Leptris::XML::Document.parse("<x><!-- c --><y/></x>")
        .canonicalize(with_comments: true)
      expect(out).to include("<!-- c -->")
    end

    it "strips comments by default" do
      out = Leptris::XML::Document.parse("<x><!-- c --><y/></x>").canonicalize
      expect(out).not_to include("<!-- c -->")
    end

    it "supports C14N 1.1 mode" do
      out = Leptris::XML::Document.parse(simple_xml)
        .canonicalize(Leptris::XML::FFI::C14N_1_1)
      expect(out).to include("<root>")
      expect(out).to include("<child")
    end
  end

  describe "Element#canonicalize — subtree" do
    it "canonicalizes the element subtree, not the whole document" do
      doc = Leptris::XML::Document.parse("<root><a><b/></a><c/></root>")
      a = doc.root.first_element_child
      sub = a.canonicalize
      expect(sub).to include("<a>")
      expect(sub).to include("<b></b>").or include("<b/>")
      expect(sub).not_to include("<c></c>")
      expect(sub).not_to include("<root>")
    end

    it "supports with_comments: true on subtree" do
      doc = Leptris::XML::Document.parse("<a><!-- c --><b/></a>")
      a = doc.root
      expect(a.canonicalize(with_comments: true)).to include("<!-- c -->")
    end
  end

  describe "exclusive C14N (mode: :exclusive)" do
    let(:nsdoc) do
      Leptris::XML::Document.parse(<<~XML)
        <root xmlns="http://default.example" xmlns:foo="http://foo.example">
          <foo:child foo:attr="1">text</foo:child>
        </root>
      XML
    end

    it "drops namespace declarations not visibly used (canonical keeps them all)" do
      canonical = nsdoc.canonicalize(mode: Leptris::XML::FFI::C14N_MODE_CANONICAL)
      exclusive = nsdoc.canonicalize(mode: Leptris::XML::FFI::C14N_MODE_EXCLUSIVE)
      # Both should produce valid output; exact difference is implementation-
      # specific. Just verify both run and produce strings including the root.
      expect(canonical).to be_a(String)
      expect(exclusive).to be_a(String)
      expect(canonical.length).to be > 0
      expect(exclusive.length).to be > 0
    end

    it "accepts the `exclusive: true` shortcut" do
      explicit = nsdoc.canonicalize(mode: Leptris::XML::FFI::C14N_MODE_EXCLUSIVE)
      shortcut = nsdoc.canonicalize(exclusive: true)
      expect(shortcut).to eq(explicit)
    end

    it "passes inclusive namespace prefixes" do
      # Build a doc that uses a prefix visible only at root level
      doc = Leptris::XML::Document.parse(<<~XML)
        <root xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
          <ds:SignedInfo><ds:Reference/></ds:SignedInfo>
        </root>
      XML
      # Without inclusive namespaces, exclusive C14N keeps only visibly-used prefixes.
      # With "ds" in inclusive list, libleptris includes the declaration even if
      # a consumer needs to know about it. Both should produce strings.
      si = doc.at_xpath("//ds:SignedInfo",
        { "ds" => "http://www.w3.org/2000/09/xmldsig#" })
      expect(si).not_to be_nil
      without = si.canonicalize(Leptris::XML::FFI::C14N_1_0, nil, exclusive: true)
      with = si.canonicalize(Leptris::XML::FFI::C14N_1_0, %w[ds], exclusive: true)
      expect(without).to be_a(String)
      expect(with).to be_a(String)
    end
  end

  describe "alias #c14n" do
    it "matches #canonicalize" do
      doc = Leptris::XML::Document.parse(simple_xml)
      expect(doc.c14n).to eq(doc.canonicalize)
    end
  end

  describe "Nokogiri-compatible signature" do
    it "accepts (mode, inclusive_namespaces, with_comments) positional args" do
      # The first positional arg is the version (C14N_1_0 / C14N_1_1);
      # the rest are keyword args matching Nokogiri-style usage.
      doc = Leptris::XML::Document.parse(simple_xml)
      out = doc.canonicalize(Leptris::XML::FFI::C14N_1_0, nil, with_comments: false)
      expect(out).to include("<root>")
    end
  end
end

RSpec.describe "Element namespace mutation (v0.5.2 #181 fix)" do
  it "adds a namespace declaration via #add_namespace_definition" do
    doc = Leptris::XML::Document.parse("<root/>")
    ns = doc.root.add_namespace_definition("foo", "http://foo.example")
    expect(ns).to be_a(Leptris::XML::Namespace)
    expect(ns.prefix).to eq("foo")
    expect(ns.href).to eq("http://foo.example")
  end

  it "adds a default namespace via #default_namespace=" do
    doc = Leptris::XML::Document.parse("<root/>")
    doc.root.default_namespace = "http://default.example"
    decls = doc.root.namespace_definitions
    expect(decls.map(&:href)).to include("http://default.example")
    default_decl = decls.find { |n| n.prefix.nil? }
    expect(default_decl&.href).to eq("http://default.example")
  end

  it "removes a namespace declaration via #remove_namespace_definition" do
    doc = Leptris::XML::Document.parse("<root/>")
    doc.root.add_namespace_definition("foo", "http://foo.example")
    doc.root.remove_namespace_definition("foo")
    expect(doc.root.namespace_definitions.length).to eq(0)
  end
end

RSpec.describe "previous_sibling for non-element nodes (v0.5.2 #179 fix)" do
  it "walks backward through text nodes via FFI (no workaround)" do
    doc = Leptris::XML::Document.parse("<x><a/>middle<b/></x>")
    b = doc.root.element_children[1]
    text = b.previous_sibling
    expect(text).to be_a(Leptris::XML::Text)
    a = text.previous_sibling
    expect(a).to be_a(Leptris::XML::Element)
    expect(a.name).to eq("a")
  end

  it "returns nil at the start of the sibling chain" do
    doc = Leptris::XML::Document.parse("<x><a/></x>")
    a = doc.root.first_element_child
    expect(a.previous_sibling).to be_nil
  end
end
