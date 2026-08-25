# frozen_string_literal: true

require "spec_helper"

RSpec.describe "read-path performance surface" do
  describe "UTF-8 at the FFI seam" do
    it "returns UTF-8 strings for names, content, and attribute values" do
      doc = Leptris::XML.parse(%(<r a="1">café</r>))
      expect(doc.root.name.encoding).to eq(Encoding::UTF_8)
      expect(doc.root["a"].encoding).to eq(Encoding::UTF_8)
      expect(doc.root.content.encoding).to eq(Encoding::UTF_8)
      expect(doc.root.content).to eq("café")
    end

    it "returns UTF-8 for path, pull attributes, and fragment content" do
      doc = Leptris::XML.parse(%(<r lang="en"/>))
      expect(doc.root.path.encoding).to eq(Encoding::UTF_8)
      events = []
      Leptris::XML::Pull.parse(%(<r k="v"/>)) { |e| events << e }
      attrs = events.first.attrs
      expect(attrs["k"].encoding).to eq(Encoding::UTF_8)
    end
  end

  describe "readonly memoization coverage" do
    let(:doc) do
      Leptris::XML.parse(
        %(<r xmlns:p="urn:p"><c p:a="1" plain="2">t<b/></c></r>),
        readonly: true)
    end
    let(:child) { doc.root.element_children.first }

    it "memoizes namespace reads" do
      expect(child.namespace_definitions).to equal(child.namespace_definitions)
      expect(child.namespaces).to equal(child.namespaces)
      expect(child.namespace).to equal(child.namespace)
    end

    it "memoizes attribute listings" do
      expect(child.keys).to equal(child.keys)
      expect(child.values).to equal(child.values)
      expect(child.attribute_nodes).to equal(child.attribute_nodes)
    end

    it "memoizes node paths and element children" do
      expect(child.path).to equal(child.path)
      expect(child.css_path).to equal(child.css_path)
      expect(child.element_children).to equal(child.element_children)
    end

    it "memoizes text content on non-element nodes" do
      text = child.children.find(&:text?)
      expect(text.content).to equal(text.content)
    end

    it "memoizes document-level PIs" do
      doc.add_pi("x", "y") rescue nil # readonly raises; PIs still memoize on the parsed doc
      expect(doc.processing_instructions)
        .to equal(doc.processing_instructions)
    end

    it "does not memoize on writable documents" do
      writable = Leptris::XML.parse(
        %(<r xmlns:p="urn:p"><c p:a="1"/></r>))
      c = writable.root.element_children.first
      expect(c.namespaces).not_to equal(c.namespaces)
      writable.root.element_children.first["p:a"] = "2"
      expect(c["p:a"]).to eq("2")
    end
  end

  describe "CSS translation cache" do
    it "returns the cached translation for repeated rules" do
      first = Leptris::XML::CssToXPath.convert("item > name")
      expect(Leptris::XML::CssToXPath.convert("item > name"))
        .to equal(first)
    end

    it "does not cache failed translations" do
      expect { Leptris::XML::CssToXPath.convert("a:unknown-pseudo") }
        .to raise_error(ArgumentError)
      expect { Leptris::XML::CssToXPath.convert("a:unknown-pseudo") }
        .to raise_error(ArgumentError)
    end
  end

  describe "Attr micro-paths" do
    it "escapes all five entities in one pass" do
      attr = Leptris::XML::Attr.new("k", %(<a & "b" 'c'>), nil)
      expect(attr.to_xml).to eq(%(k="&lt;a &amp; &quot;b&quot; &apos;c&apos;&gt;"))
    end

    it "answers prefix without allocation churn" do
      expect(Leptris::XML::Attr.new("p:k", "v", nil).prefix).to eq("p")
      expect(Leptris::XML::Attr.new("k", "v", nil).prefix).to be_nil
    end
  end
end
