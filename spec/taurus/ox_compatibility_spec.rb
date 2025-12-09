# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Ox Compatibility" do
  describe "Basic parsing" do
    it "parses simple XML" do
      xml = "<top>test</top>"
      doc = Taurus.parse(xml)

      expect(doc).to be_a(Taurus::Document)
      expect(doc.root.name).to eq("top")
      expect(doc.root.text).to eq("test")
    end

    it "parses XML with attributes" do
      xml = '<top name="Pete">test</top>'
      doc = Taurus.parse(xml)

      expect(doc.root["name"]).to eq("Pete")
    end

    it "parses nested elements" do
      xml = '<top><nested>value</nested></top>'
      doc = Taurus.parse(xml)

      expect(doc.root.nodes.size).to eq(1)
      expect(doc.root.nodes[0].name).to eq("nested")
      expect(doc.root.nodes[0].text).to eq("value")
    end
  end

  describe "Namespace support" do
    it "parses default namespace declaration" do
      xml = '<root xmlns="http://example.org">content</root>'
      doc = Taurus.parse(xml)

      expect(doc.root.namespace).not_to be_nil
      expect(doc.root.namespace[:href]).to eq("http://example.org")
      expect(doc.root.namespace[:prefix]).to be_nil
    end

    it "parses prefixed namespace declaration" do
      xml = '<root xmlns:ex="http://example.org">content</root>'
      doc = Taurus.parse(xml)

      expect(doc.root.namespaces.size).to eq(1)
      ns = doc.root.namespaces[0]
      expect(ns[:prefix]).to eq("ex")
      expect(ns[:href]).to eq("http://example.org")
    end

    it "parses multiple namespace declarations" do
      xml = '<root xmlns="http://default.org" xmlns:ex="http://example.org" xmlns:ns="http://another.org">content</root>'
      doc = Taurus.parse(xml)

      expect(doc.root.namespaces.size).to eq(3)
    end

    it "parses namespaced elements" do
      xml = '<root xmlns:ex="http://example.org"><ex:item>test</ex:item></root>'
      doc = Taurus.parse(xml)

      item = doc.root.nodes[0]
      expect(item.name).to eq("item")
      expect(item.namespace).not_to be_nil
      expect(item.namespace[:prefix]).to eq("ex")
      expect(item.namespace[:href]).to eq("http://example.org")
    end

    it "parses namespaced attributes" do
      xml = '<root xmlns:ex="http://example.org" ex:name="value">content</root>'
      doc = Taurus.parse(xml)

      # Namespaced attributes are stored in the attributes hash
      expect(doc.root["ex:name"]).to eq("value")
    end
  end

  describe "Namespace inheritance" do
    it "inherits default namespace to child elements" do
      xml = '<root xmlns="http://example.org"><child>content</child></root>'
      doc = Taurus.parse(xml)

      child = doc.root.nodes[0]
      expect(child.namespace).not_to be_nil
      expect(child.namespace[:href]).to eq("http://example.org")
    end

    it "inherits prefixed namespace to child elements" do
      xml = '<root xmlns:ex="http://example.org"><child><ex:item>test</ex:item></child></root>'
      doc = Taurus.parse(xml)

      item = doc.root.nodes[0].nodes[0]
      expect(item.namespace).not_to be_nil
      expect(item.namespace[:prefix]).to eq("ex")
      expect(item.namespace[:href]).to eq("http://example.org")
    end

    it "allows namespace redeclaration in child elements" do
      xml = '<root xmlns:ex="http://example.org"><child xmlns:ex="http://other.org"><ex:item>test</ex:item></child></root>'
      doc = Taurus.parse(xml)

      item = doc.root.nodes[0].nodes[0]
      expect(item.namespace).not_to be_nil
      expect(item.namespace[:prefix]).to eq("ex")
      expect(item.namespace[:href]).to eq("http://other.org")
    end
  end

  describe "Namespace resolution" do
    it "resolves prefixes using namespace_for_prefix" do
      xml = '<root xmlns:ex="http://example.org"><ex:item>test</ex:item></root>'
      doc = Taurus.parse(xml)

      href = doc.root.namespace_for_prefix("ex")
      expect(href).to eq("http://example.org")
    end

    it "resolves default namespace with nil prefix" do
      xml = '<root xmlns="http://default.org">content</root>'
      doc = Taurus.parse(xml)

      href = doc.root.namespace_for_prefix(nil)
      expect(href).to eq("http://default.org")
    end

    it "resolves inherited namespaces" do
      xml = '<root xmlns:ex="http://example.org"><child><ex:item>test</ex:item></child></root>'
      doc = Taurus.parse(xml)

      href = doc.root.nodes[0].namespace_for_prefix("ex")
      expect(href).to eq("http://example.org")
    end
  end

  describe "Special XML features" do
    it "parses comments" do
      xml = '<root><!-- This is a comment -->content</root>'
      doc = Taurus.parse(xml)

      # Comments are stored as nodes
      expect(doc.root.nodes.size).to eq(2)
      expect(doc.root.nodes[0]).to be_a(String) # The comment text
      expect(doc.root.nodes[1]).to eq("content") # The text content
    end

    it "parses CDATA sections" do
      xml = '<root><![CDATA[<item>content</item>]]></root>'
      doc = Taurus.parse(xml)

      expect(doc.root.text).to eq("<item>content</item>")
    end

    it "parses self-closing elements" do
      xml = '<root><item/></root>'
      doc = Taurus.parse(xml)

      expect(doc.root.nodes.size).to eq(1)
      expect(doc.root.nodes[0].name).to eq("item")
    end
  end

  describe "Error handling" do
    it "handles malformed XML gracefully" do
      xml = '<top>test</topz>' # Mismatched tag
      expect { Taurus.parse(xml) }.to raise_error(Taurus::ParseError)
    end

    it "handles mismatched tags" do
      xml = '<top><nested>test</top>' # Missing closing tag for nested
      expect { Taurus.parse(xml) }.to raise_error(Taurus::ParseError)
    end
  end
end