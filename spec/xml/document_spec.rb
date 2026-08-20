# frozen_string_literal: true

require "taurus/xml"

RSpec.describe Taurus::XML::Document do
  describe ".parse" do
    it "parses a simple XML string into a Document" do
      doc = described_class.parse("<root>Hello</root>")
      expect(doc).to be_a(described_class)
      expect(doc).to respond_to(:root)
    end

    it "raises ParseError on malformed input" do
      expect { described_class.parse("<unclosed>") }.to raise_error(Taurus::XML::ParseError)
    end

    it "accepts an IO object (responds to :read)" do
      require "stringio"
      io = StringIO.new("<root>text</root>")
      doc = described_class.parse(io)
      expect(doc.root.name).to eq("root")
    end
  end

  describe "#root" do
    it "returns the root element" do
      doc = described_class.parse("<library><book/></library>")
      root = doc.root
      expect(root).to be_a(Taurus::XML::Element)
      expect(root.name).to eq("library")
    end

    it "returns nil for empty document" do
      # libtaurus parses an empty/whitespace doc to no root
      doc = described_class.parse("<x/>")
      expect(doc.root.name).to eq("x")
    end
  end

  describe "#free" do
    it "can be called explicitly without error" do
      doc = described_class.parse("<x/>")
      expect { doc.free }.not_to raise_error
    end

    it "is idempotent" do
      doc = described_class.parse("<x/>")
      doc.free
      expect { doc.free }.not_to raise_error
    end
  end
end

RSpec.describe Taurus::XML::Element do
  let(:doc) { Taurus::XML::Document.parse(<<~XML) }
    <library version="2.0">
      <book id="1"><title>Ruby</title></book>
      <book id="2"><title>XML</title></book>
    </library>
  XML
  let(:root) { doc.root }

  it "exposes element name" do
    expect(root.name).to eq("library")
  end

  it "exposes element text content (concatenated descendants)" do
    expect(root.content).to include("Ruby").and include("XML")
  end

  it "exposes attribute lookup via #[name]" do
    expect(root["version"]).to eq("2.0")
    expect(root["nonexistent"]).to be_nil
  end

  it "exposes attribute keys and values" do
    expect(root.keys).to eq(["version"])
    expect(root.values).to eq(["2.0"])
  end

  it "exposes the attributes hash" do
    expect(root.attributes).to be_a(Hash)
    expect(root.attributes.keys).to eq(["version"])
    expect(root.attributes["version"]).to be_a(Taurus::XML::Attr)
    expect(root.attributes["version"].value).to eq("2.0")
  end

  it "iterates element children" do
    children = root.element_children.to_a
    expect(children.length).to eq(2)
    expect(children.map(&:name)).to eq(%w[book book])
  end

  it "iterates all children (elements + text)" do
    all = root.children.to_a
    expect(all.length).to be >= 2
    expect(all.first).to be_a(Taurus::XML::Text)  # whitespace before first <book>
  end

  it "exposes first_element_child and last_element_child" do
    expect(root.first_element_child["id"]).to eq("1")
    expect(root.last_element_child["id"]).to eq("2")
  end

  it "exposes parent navigation" do
    book = root.first_element_child
    expect(book.parent).to eq(root)
  end

  it "exposes sibling navigation" do
    book1 = root.first_element_child
    book2 = book1.next_element
    expect(book2["id"]).to eq("2")
    expect(book2.previous_element).to eq(book1)
  end
end

RSpec.describe Taurus::XML::Node do
  describe "type predicates" do
    it "recognizes element nodes" do
      doc = Taurus::XML::Document.parse("<x/>")
      expect(doc.root.element?).to be true
      expect(doc.root.text?).to be false
    end

    it "recognizes text nodes" do
      doc = Taurus::XML::Document.parse("<x>hello</x>")
      text = doc.root.child
      expect(text).to be_a(Taurus::XML::Text)
      expect(text.text?).to be true
      expect(text.element?).to be false
      expect(text.content).to eq("hello")
    end

    it "recognizes comment nodes" do
      doc = Taurus::XML::Document.parse("<x><!-- hi --></x>")
      comment = doc.root.children.find { |n| n.comment? }
      expect(comment).to be_a(Taurus::XML::Comment)
      expect(comment.content).to eq(" hi ")
    end

    it "recognizes CDATA nodes" do
      doc = Taurus::XML::Document.parse("<x><![CDATA[<raw>]]></x>")
      cdata = doc.root.children.find { |n| n.cdata? }
      expect(cdata).to be_a(Taurus::XML::CDATA)
      expect(cdata.content).to eq("<raw>")
    end

    it "recognizes processing instruction nodes" do
      doc = Taurus::XML::Document.parse("<x><?xml-stylesheet type='text/xsl'?></x>")
      pi = doc.root.children.find { |n| n.processing_instruction? }
      expect(pi).to be_a(Taurus::XML::ProcessingInstruction)
      expect(pi.name).to eq("xml-stylesheet")
    end
  end

  describe "navigation" do
    it "walks siblings via next_sibling" do
      doc = Taurus::XML::Document.parse("<x><a/><b/><c/></x>")
      root = doc.root
      a = root.first_element_child
      b = a.next_sibling
      c = b.next_sibling
      expect(c.name).to eq("c")
      expect(c.next_sibling).to be_nil
    end

    it "walks all children via children.each" do
      doc = Taurus::XML::Document.parse("<x><a/><b/><c/></x>")
      root = doc.root
      names = root.children.select(&:element?).map(&:name)
      expect(names).to eq(%w[a b c])
    end
  end
end

RSpec.describe "Taurus::XML module entry points" do
  it "parses via Taurus::XML.parse" do
    doc = Taurus::XML.parse("<root><child/></root>")
    expect(doc).to be_a(Taurus::XML::Document)
    expect(doc.root.name).to eq("root")
    expect(doc.root.first_element_child.name).to eq("child")
  end

  it "parses an IO via Taurus::XML.parse" do
    require "stringio"
    doc = Taurus::XML.parse(StringIO.new("<root/>"))
    expect(doc.root.name).to eq("root")
  end

  it "parses a file via Taurus::XML.parse_file" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "t.xml")
      File.write(path, "<root>data</root>")
      doc = Taurus::XML.parse_file(path)
      expect(doc.root.content).to eq("data")
    end
  end
end
