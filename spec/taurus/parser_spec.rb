# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Taurus XML Parser with Namespace Support" do
  describe "basic XML parsing" do
    it "parses simple XML without namespaces" do
      xml = '<root><item>content</item></root>'
      doc = Taurus.parse(xml)

      expect(doc).to be_a(Taurus::Document)
      expect(doc.root).to be_a(Taurus::Element)
      expect(doc.root.name).to eq("root")
      expect(doc.root.nodes.size).to eq(1)
      expect(doc.root.nodes.first.name).to eq("item")
      expect(doc.root.nodes.first.text).to eq("content")
    end

    it "parses XML with attributes" do
      xml = '<root id="123"><item attr="value">text</item></root>'
      doc = Taurus.parse(xml)

      expect(doc.root.attributes["id"]).to eq("123")
      expect(doc.root.nodes.first.attributes["attr"]).to eq("value")
      expect(doc.root.nodes.first.text).to eq("text")
    end

    it "parses nested elements" do
      xml = '<root><parent><child>deep</child></parent></root>'
      doc = Taurus.parse(xml)

      parent = doc.root.nodes.first
      expect(parent.name).to eq("parent")
      expect(parent.nodes.first.name).to eq("child")
      expect(parent.nodes.first.text).to eq("deep")
    end
  end

  describe "namespace parsing" do
    it "parses default namespace declaration" do
      xml = '<root xmlns="http://example.org"><item>content</item></root>'
      doc = Taurus.parse(xml)

      expect(doc.root.namespace_uri).to eq("http://example.org")
      expect(doc.root.namespace_prefix).to be_nil
    end

    it "parses prefixed namespace declaration" do
      xml = '<root xmlns:ex="http://example.org"><ex:item>content</ex:item></root>'
      doc = Taurus.parse(xml)

      expect(doc.root.namespaces.size).to eq(1)
      expect(doc.root.namespaces.first[:prefix]).to eq("ex")
      expect(doc.root.namespaces.first[:href]).to eq("http://example.org")
    end

    it "parses multiple namespace declarations" do
      xml = '<root xmlns="http://default.org" xmlns:ex="http://example.org" xmlns:other="http://other.org"/>'
      doc = Taurus.parse(xml)

      expect(doc.root.namespaces.size).to eq(3)

      # Find each namespace
      default_ns = doc.root.namespaces.find { |ns| ns[:prefix].nil? }
      ex_ns = doc.root.namespaces.find { |ns| ns[:prefix] == "ex" }
      other_ns = doc.root.namespaces.find { |ns| ns[:prefix] == "other" }

      expect(default_ns[:href]).to eq("http://default.org")
      expect(ex_ns[:href]).to eq("http://example.org")
      expect(other_ns[:href]).to eq("http://other.org")
    end

    it "parses namespaced elements" do
      xml = '<root xmlns:ex="http://example.org"><ex:item>content</ex:item></root>'
      doc = Taurus.parse(xml)

      item = doc.root.nodes.first
      expect(item.name).to eq("item")  # Local name only (Ox compatibility)
      expect(item.qualified_name).to eq("ex:item")  # Full qualified name with prefix
      expect(item.namespace_prefix).to eq("ex")
      expect(item.namespace_uri).to eq("http://example.org")
    end

    it "parses namespaced attributes" do
      xml = '<root xmlns:ex="http://example.org"><item ex:attr="value">content</item></root>'
      doc = Taurus.parse(xml)

      item = doc.root.nodes.first
      expect(item.attributes["ex:attr"]).to eq("value")
    end
  end

  describe "namespace inheritance" do
    it "inherits default namespace to child elements" do
      xml = '<root xmlns="http://example.org"><item>content</item></root>'
      doc = Taurus.parse(xml)

      item = doc.root.nodes.first
      expect(item.namespace_uri).to eq("http://example.org")
      expect(item.namespace_prefix).to be_nil
    end

    it "inherits prefixed namespace to child elements" do
      xml = '<root xmlns:ex="http://example.org"><ex:item><ex:child>content</ex:child></ex:item></root>'
      doc = Taurus.parse(xml)

      item = doc.root.nodes.first
      child = item.nodes.first

      expect(item.namespace_uri).to eq("http://example.org")
      expect(child.namespace_uri).to eq("http://example.org")
    end

    it "allows namespace redeclaration in child elements" do
      xml = '<root xmlns="http://default.org"><item xmlns="http://new.org">content</item></root>'
      doc = Taurus.parse(xml)

      expect(doc.root.namespace_uri).to eq("http://default.org")
      expect(doc.root.nodes.first.namespace_uri).to eq("http://new.org")
    end
  end

  describe "namespace resolution" do
    it "resolves prefixes using namespace_for_prefix" do
      xml = '<root xmlns:ex="http://example.org" xmlns:other="http://other.org"/>'
      doc = Taurus.parse(xml)

      expect(doc.root.namespace_for_prefix("ex")).to eq("http://example.org")
      expect(doc.root.namespace_for_prefix("other")).to eq("http://other.org")
      expect(doc.root.namespace_for_prefix("nonexistent")).to be_nil
    end

    it "resolves default namespace with nil prefix" do
      xml = '<root xmlns="http://default.org"/>'
      doc = Taurus.parse(xml)

      expect(doc.root.namespace_for_prefix(nil)).to eq("http://default.org")
    end

    it "resolves inherited namespaces" do
      xml = '<root xmlns:ex="http://example.org"><item><child/></item></root>'
      doc = Taurus.parse(xml)

      child = doc.root.nodes.first.nodes.first
      expect(child.namespace_for_prefix("ex")).to eq("http://example.org")
    end
  end

  describe "complex namespace scenarios" do
    it "handles mixed default and prefixed namespaces" do
      xml = <<~XML
        <root xmlns="http://default.org" xmlns:ex="http://example.org">
          <item>default</item>
          <ex:item>prefixed</ex:item>
        </root>
      XML

      doc = Taurus.parse(xml.strip)

      default_item = doc.root.nodes[0]
      prefixed_item = doc.root.nodes[1]

      expect(default_item.namespace_uri).to eq("http://default.org")
      expect(prefixed_item.namespace_uri).to eq("http://example.org")
      expect(prefixed_item.namespace_prefix).to eq("ex")
    end

    it "handles deeply nested namespaces" do
      xml = <<~XML
        <root xmlns="http://root.org" xmlns:a="http://a.org">
          <level1 xmlns:b="http://b.org">
            <level2 xmlns:c="http://c.org">
              <level3>content</level3>
            </level2>
          </level1>
        </root>
      XML

      doc = Taurus.parse(xml.strip)

      level1 = doc.root.nodes.first
      level2 = level1.nodes.first
      level3 = level2.nodes.first

      expect(level1.namespace_uri).to eq("http://root.org")
      expect(level2.namespace_uri).to eq("http://root.org")
      expect(level3.namespace_uri).to eq("http://root.org")

      expect(level1.namespace_for_prefix("a")).to eq("http://a.org")
      expect(level1.namespace_for_prefix("b")).to eq("http://b.org")
      expect(level2.namespace_for_prefix("c")).to eq("http://c.org")
    end
  end

  describe "error handling" do
    it "handles malformed XML gracefully" do
      xml = '<root><item>unclosed'

      expect { Taurus.parse(xml) }.to raise_error(Taurus::ParseError)
    end

    it "handles mismatched tags" do
      xml = '<root><item></wrong></root>'

      expect { Taurus.parse(xml) }.to raise_error(Taurus::ParseError)
    end

    it "handles invalid characters in names" do
      xml = '<root><123invalid>content</123invalid></root>'

      expect { Taurus.parse(xml) }.to raise_error(Taurus::ParseError)
    end
  end

  describe "special XML features" do
    it "parses comments" do
      xml = '<root><!-- This is a comment --><item>content</item></root>'
      doc = Taurus.parse(xml)

      expect(doc.root.nodes.size).to eq(2)  # Comment text + element
      expect(doc.root.nodes[0]).to be_a(String)  # The comment text
      expect(doc.root.nodes[1].name).to eq("item")
    end

    it "parses CDATA sections" do
      xml = '<root><item><![CDATA[<special>content</special>]]></item></root>'
      doc = Taurus.parse(xml)

      expect(doc.root.nodes.first.text).to include("<special>content</special>")
    end

    it "parses self-closing elements" do
      xml = '<root><item/></root>'
      doc = Taurus.parse(xml)

      expect(doc.root.nodes.size).to eq(1)
      expect(doc.root.nodes.first.name).to eq("item")
    end
  end

  describe "file parsing" do
    it "parses XML from file" do
      require 'tempfile'

      xml = '<root><item>content</item></root>'

      Tempfile.create(['test', '.xml']) do |file|
        file.write(xml)
        file.close

        doc = Taurus.parse_file(file.path)
        expect(doc.root.name).to eq("root")
        expect(doc.root.nodes.first.name).to eq("item")
      end
    end

    it "handles missing file gracefully" do
      expect { Taurus.parse_file("/nonexistent/file.xml") }.to raise_error(Errno::ENOENT)
    end
  end

  describe "all_namespaces method" do
    it "returns all namespaces including inherited" do
      xml = <<~XML
        <root xmlns="http://root.org" xmlns:a="http://a.org">
          <child xmlns:b="http://b.org">
            <grandchild/>
          </child>
        </root>
      XML

      doc = Taurus.parse(xml.strip)

      root = doc.root
      child = root.nodes.first
      grandchild = child.nodes.first

      expect(root.all_namespaces).to eq({
        nil => "http://root.org",
        "a" => "http://a.org"
      })

      expect(child.all_namespaces).to eq({
        nil => "http://root.org",
        "a" => "http://a.org",
        "b" => "http://b.org"
      })

      expect(grandchild.all_namespaces).to eq({
        nil => "http://root.org",
        "a" => "http://a.org",
        "b" => "http://b.org"
      })
    end
  end
end