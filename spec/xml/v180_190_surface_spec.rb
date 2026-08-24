# frozen_string_literal: true

require "spec_helper"

RSpec.describe "libleptris 1.8.0 / 1.9.0 surface" do
  describe "expanded-name attribute access (1.8.0, #542)" do
    let(:doc) do
      Leptris::XML.parse(<<~XML)
        <r xmlns:p="urn:p" xmlns:q="urn:p" xmlns="urn:d"
           p:id="1" q:ref="2" plain="3" xml:lang="en"/>
      XML
    end
    let(:root) { doc.root }

    it "looks up by (uri, local) regardless of the written prefix" do
      expect(root.attribute_ns("urn:p", "id")).to eq("1")
      expect(root.attribute_ns("urn:p", "ref")).to eq("2")
    end

    it "matches no-namespace attributes with a nil or empty uri" do
      expect(root.attribute_ns(nil, "plain")).to eq("3")
      expect(root.attribute_ns("", "plain")).to eq("3")
    end

    it "does not match qualified attributes from the default namespace" do
      expect(root.attribute_ns("urn:d", "id")).to be_nil
    end

    it "resolves the prebound xml prefix" do
      expect(root.attribute_ns("http://www.w3.org/XML/1998/namespace",
                               "lang")).to eq("en")
    end

    it "never matches xmlns declarations" do
      expect(root.attribute_ns("http://www.w3.org/2000/xmlns/", "p")).to be_nil
      expect(root.attribute_ns(nil, "xmlns")).to be_nil
    end

    it "answers presence with has_attribute_ns?" do
      expect(root.has_attribute_ns?("urn:p", "id")).to be true
      expect(root.has_attribute_ns?(nil, "id")).to be false
      expect(root.has_attribute_ns?("urn:nope", "id")).to be false
    end
  end

  describe "Attr#prefix / Attr#namespace_uri (1.8.0, #542)" do
    let(:doc) do
      Leptris::XML.parse(
        %(<r xmlns:p="urn:p" p:a="1" plain="2" xml:lang="en" undecl:u="3"/>))
    end
    let(:attrs) { doc.root.attribute_nodes }

    it "reports the written prefix" do
      expect(attrs.find { |a| a.name == "p:a" }.prefix).to eq("p")
      expect(attrs.find { |a| a.name == "plain" }.prefix).to be_nil
    end

    it "resolves the URI through the owning element's declarations" do
      expect(attrs.find { |a| a.name == "p:a" }.namespace_uri).to eq("urn:p")
    end

    it "prebinds xml and returns nil for undeclared prefixes" do
      expect(attrs.find { |a| a.name.start_with?("xml:") }
        .namespace_uri).to eq("http://www.w3.org/XML/1998/namespace")
      expect(attrs.find { |a| a.name == "undecl:u" }.namespace_uri).to be_nil
      expect(attrs.find { |a| a.name == "plain" }.namespace_uri).to be_nil
    end

    it "serves namespace as an alias" do
      expect(attrs.first.namespace).to eq(attrs.first.namespace_uri)
    end
  end

  describe "namespaces-correct by-name access (1.8.0)" do
    it "matches qualified names through declarations, not spelling" do
      doc = Leptris::XML.parse(
        %(<r xmlns:a="urn:x" xmlns:b="urn:x" a:k="1" b:k="2" k="3"/>))
      root = doc.root
      # a:k and b:k share the expanded name (urn:x, k): both spellings
      # resolve to the first attribute with that expanded name.
      expect(root["a:k"]).to eq("1")
      expect(root["b:k"]).to eq("1")
      # Bare names match only the no-namespace attribute.
      expect(root["k"]).to eq("3")
      # Undeclared prefixes are NULL.
      expect(root["c:k"]).to be_nil
    end
  end

  describe "detached sibling inserts (1.8.0, #540)" do
    it "supports bottom-up construction from detached elements" do
      doc = Leptris::XML::Document.create
      p = doc.create_element("p")
      a = doc.create_element("a")
      b = doc.create_element("b")
      c = doc.create_element("c")
      a.add_next_sibling(b)   # all three detached
      b.add_next_sibling(c)
      expect(a.next_sibling.name).to eq("b")
      p.add_child(a)          # attaching the head carries the chain
      doc.root = p
      expect(doc.root.children.map(&:name)).to eq(%w[a b c])
      expect(doc.to_xml(no_decl: true)).to eq("<p><a/><b/><c/></p>")
    end
  end

  describe "recover parsing (1.9.0, #547)" do
    it "raises ParseError without recover" do
      expect { Leptris::XML.parse("<broken") }
        .to raise_error(Leptris::XML::ParseError)
    end

    it "returns an empty document with recover: true" do
      doc = Leptris::XML.parse("<broken", recover: true)
      expect(doc).to be_a(Leptris::XML::Document)
      expect(doc.root).to be_nil
      expect(Leptris::XML::FFI.leptris_last_error).not_to be_empty
    end

    it "is reachable via ParseOptions and merges with noblanks" do
      opts = Leptris::XML::ParseOptions.noblanks |
             Leptris::XML::ParseOptions.recovering
      expect(opts.recover?).to be true
      expect(opts.noblanks?).to be true
      doc = Leptris::XML.parse("<broken", options: opts)
      expect(doc.root).to be_nil
    end

    it "still parses well-formed input under recover" do
      doc = Leptris::XML.parse("<r><a/></r>", recover: true)
      expect(doc.root.name).to eq("r")
    end
  end

  describe "rootless documents with PIs serialize (1.9.0, #546)" do
    it "emits document-level PIs instead of an empty string" do
      doc = Leptris::XML::Document.create
      doc.add_pi("xml-stylesheet", %(type="text/xsl" href="s.xsl"))
      expect(doc.to_xml)
        .to include(%(<?xml-stylesheet type="text/xsl" href="s.xsl"?>))
    end
  end

  describe "caller-buffer serialization (1.9.0, #541)" do
    it "round-trips document and element output byte-for-byte" do
      xml = %(<r a="&lt;&gt;&quot;&amp;"><a/>text<c d="1"/></r>)
      doc = Leptris::XML.parse(xml)
      reparsed = Leptris::XML.parse(doc.to_xml)
      expect(reparsed.root.to_xml).to eq(doc.root.to_xml)
      expect(doc.root.to_xml).to include(%(a="&lt;&gt;&quot;&amp;"))
    end

    it "honors indent, no_decl, and encoding through the into path" do
      doc = Leptris::XML.parse("<r><a/></r>")
      expect(doc.to_xml(no_decl: true)).to eq("<r><a/></r>")
      expect(doc.to_xml(indent: 2)).to include("\n  <a/>")
      expect(doc.to_xml(encoding: "UTF-8"))
        .to start_with(%(<?xml version="1.0" encoding="UTF-8"?>))
    end

    it "invalidates the cache on mutation" do
      doc = Leptris::XML.parse("<r><a><b/></a></r>")
      3.times { expect(doc.to_xml).to eq(doc.to_xml) }
      doc.root << doc.root.xpath("//b").first.dup
      expect(doc.to_xml).to include("<a><b/></a><b/>")
    end
  end
end
