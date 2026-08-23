# frozen_string_literal: true

require "spec_helper"

RSpec.describe "programmatic document construction" do
  describe ".create" do
    it "returns a document with no root" do
      doc = Leptris::XML::Document.create
      expect(doc).to be_a(Leptris::XML::Document)
      expect(doc.root).to be_nil
    end

    it "produces a document whose factories work" do
      doc = Leptris::XML::Document.create
      expect(doc.create_element("r")).to be_a(Leptris::XML::Element)
      expect(doc.create_text_node("x").content).to eq("x")
    end
  end

  describe "#root=" do
    it "attaches an element and serializes the tree" do
      doc = Leptris::XML::Document.create
      root = doc.create_element("root")
      doc.root = root
      child = doc.create_element("child")
      child["id"] = "1"
      root.add_child(child)
      child.content = "hello & bye"

      expect(doc.root).to equal(root)
      expect(doc.serialize).to include(%(<child id="1">hello &amp; bye</child>))
    end

    it "rejects an element from another document" do
      doc_a = Leptris::XML::Document.create
      doc_b = Leptris::XML::Document.create
      foreign = doc_b.create_element("b")

      expect { doc_a.root = foreign }
        .to raise_error(Leptris::XML::Error, /argument/i)
    end

    it "rejects an element that already has a parent" do
      doc = Leptris::XML::Document.parse("<a><b/></a>")
      b = doc.root.children.first

      expect { doc.root = b }.to raise_error(Leptris::XML::Error, /argument/i)
    end
  end
end

RSpec.describe "namespace and attribute fixes" do
  it "Element#namespace carries the element prefix" do
    doc = Leptris::XML::Document.parse(
      %(<a xmlns:p="urn:p"><p:b/></a>)
    )
    b = doc.root.children.first
    expect(b.namespace.prefix).to eq("p")
    expect(b.namespace.href).to eq("urn:p")
  end

  it "Element#namespace has a nil prefix in the default namespace" do
    doc = Leptris::XML::Document.parse(
      %(<a xmlns="urn:d"><b/></a>)
    )
    b = doc.root.children.first
    expect(b.namespace.prefix).to be_nil
    expect(b.namespace.href).to eq("urn:d")
  end

  it "Attr#to_xml serializes with escaped special characters" do
    doc = Leptris::XML::Document.parse(%(<e a="&lt; &gt; &amp; &quot; &apos;"/>))
    attr = doc.root.attribute_nodes.first
    expect(attr.value).to eq(%(< > & " '))
    expect(attr.to_xml)
      .to eq(%(a="&lt; &gt; &amp; &quot; &apos;"))
  end

  it "Node#text dispatches to the subclass #content" do
    doc = Leptris::XML::Document.parse("<a>hello</a>")
    text = doc.root.children.first
    expect(text).to be_a(Leptris::XML::Text)
    expect(text.text).to eq("hello")
    expect(text.inner_text).to eq("hello")
  end
end
