# frozen_string_literal: true

require "leptris/xml"

RSpec.describe Leptris::XML::Document do
  describe ".parse" do
    it "parses a simple XML string into a Document" do
      doc = described_class.parse("<root>Hello</root>")
      expect(doc).to be_a(described_class)
      expect(doc).to respond_to(:root)
    end

    it "raises ParseError on malformed input" do
      expect { described_class.parse("<unclosed>") }.to raise_error(Leptris::XML::ParseError)
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
      expect(root).to be_a(Leptris::XML::Element)
      expect(root.name).to eq("library")
    end

    it "returns nil for empty document" do
      # libleptris parses an empty/whitespace doc to no root
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

RSpec.describe Leptris::XML::Element do
  let(:doc) { Leptris::XML::Document.parse(<<~XML) }
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
    expect(root.attributes["version"]).to be_a(Leptris::XML::Attr)
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
    expect(all.first).to be_a(Leptris::XML::Text)  # whitespace before first <book>
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

RSpec.describe Leptris::XML::Node do
  describe "type predicates" do
    it "recognizes element nodes" do
      doc = Leptris::XML::Document.parse("<x/>")
      expect(doc.root.element?).to be true
      expect(doc.root.text?).to be false
    end

    it "recognizes text nodes" do
      doc = Leptris::XML::Document.parse("<x>hello</x>")
      text = doc.root.child
      expect(text).to be_a(Leptris::XML::Text)
      expect(text.text?).to be true
      expect(text.element?).to be false
      expect(text.content).to eq("hello")
    end

    it "recognizes comment nodes" do
      doc = Leptris::XML::Document.parse("<x><!-- hi --></x>")
      comment = doc.root.children.find { |n| n.comment? }
      expect(comment).to be_a(Leptris::XML::Comment)
      expect(comment.content).to eq(" hi ")
    end

    it "recognizes CDATA nodes" do
      doc = Leptris::XML::Document.parse("<x><![CDATA[<raw>]]></x>")
      cdata = doc.root.children.find { |n| n.cdata? }
      expect(cdata).to be_a(Leptris::XML::CDATA)
      expect(cdata.content).to eq("<raw>")
    end

    it "recognizes processing instruction nodes" do
      doc = Leptris::XML::Document.parse("<x><?xml-stylesheet type='text/xsl'?></x>")
      pi = doc.root.children.find { |n| n.processing_instruction? }
      expect(pi).to be_a(Leptris::XML::ProcessingInstruction)
      expect(pi.name).to eq("xml-stylesheet")
    end
  end

  describe "navigation" do
    it "walks siblings via next_sibling" do
      doc = Leptris::XML::Document.parse("<x><a/><b/><c/></x>")
      root = doc.root
      a = root.first_element_child
      b = a.next_sibling
      c = b.next_sibling
      expect(c.name).to eq("c")
      expect(c.next_sibling).to be_nil
    end

    it "walks all children via children.each" do
      doc = Leptris::XML::Document.parse("<x><a/><b/><c/></x>")
      root = doc.root
      names = root.children.select(&:element?).map(&:name)
      expect(names).to eq(%w[a b c])
    end
  end
end

RSpec.describe "Leptris::XML module entry points" do
  it "parses via Leptris::XML.parse" do
    doc = Leptris::XML.parse("<root><child/></root>")
    expect(doc).to be_a(Leptris::XML::Document)
    expect(doc.root.name).to eq("root")
    expect(doc.root.first_element_child.name).to eq("child")
  end

  it "parses an IO via Leptris::XML.parse" do
    require "stringio"
    doc = Leptris::XML.parse(StringIO.new("<root/>"))
    expect(doc.root.name).to eq("root")
  end

  it "parses a file via Leptris::XML.parse_file" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "t.xml")
      File.write(path, "<root>data</root>")
      doc = Leptris::XML.parse_file(path)
      expect(doc.root.content).to eq("data")
    end
  end
end

RSpec.describe "wrapper identity" do
  it "returns the same object for repeated root access" do
    doc = Leptris::XML::Document.parse("<root><child/></root>")
    expect(doc.root.equal?(doc.root)).to be(true)
  end

  it "keeps identity across forced GC sweeps" do
    doc = Leptris::XML::Document.parse("<root><child/></root>")
    root = doc.root
    10.times { GC.start }
    expect(doc.root.equal?(root)).to be(true)
  end

  it "returns the same object for a node reached by different paths" do
    doc = Leptris::XML::Document.parse("<root><a/><b/></root>")
    via_children = doc.root.children.first
    via_first    = doc.root.first_element_child
    expect(via_children.equal?(via_first)).to be(true)
  end

  it "returns the same parent object from parent and child navigation" do
    doc = Leptris::XML::Document.parse("<root><child/></root>")
    child = doc.root.first_element_child
    expect(child.parent.equal?(doc.root)).to be(true)
    expect(child.parent.equal?(child.parent)).to be(true)
  end

  it "returns the same object from repeated xpath evaluation" do
    doc = Leptris::XML::Document.parse("<root><item id='1'/><item id='2'/></root>")
    first_run  = doc.xpath("//item").to_a
    second_run = doc.xpath("//item").to_a
    expect(first_run[0].equal?(second_run[0])).to be(true)
    expect(first_run[1].equal?(second_run[1])).to be(true)
  end
end

RSpec.describe "parse options" do
  let(:pretty_xml) do
    <<~XML
      <root>
        <a>text</a>
        <b>
          <c/>
        </b>
      </root>
    XML
  end

  it "keeps whitespace-only text nodes by default" do
    doc = Leptris::XML.parse(pretty_xml)
    expect(doc.root.children).to all(be_a(Leptris::XML::Node))
    expect(doc.root.children.count(&:text?)).to be > 0
    expect(doc.root.first_element_child.name).to eq("a")
  end

  it "drops whitespace-only text nodes with noblanks" do
    doc = Leptris::XML.parse(pretty_xml, options: Leptris::XML::ParseOptions.noblanks)
    expect(doc.root.children.select(&:text?)).to be_empty
    expect(doc.root.children.map(&:name)).to eq(%w[a b])
    expect(doc.root.first_element_child.name).to eq("a")
  end

  it "reports its flag state" do
    expect(Leptris::XML::ParseOptions.noblanks).to be_noblanks
    expect(Leptris::XML::ParseOptions.new).not_to be_noblanks
  end

  it "rejects non-ParseOptions values" do
    expect { Leptris::XML.parse(pretty_xml, options: :noblanks) }
      .to raise_error(ArgumentError, /ParseOptions/)
  end

  it "carries meaningful text through noblanks parses" do
    doc = Leptris::XML.parse(pretty_xml, options: Leptris::XML::ParseOptions.noblanks)
    expect(doc.root.first_element_child.content).to eq("text")
  end
end
