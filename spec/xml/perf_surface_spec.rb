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

RSpec.describe "round III: SAX adapter and query paths" do
  class EncodingProbeHandler < Leptris::XML::SAX::Document
    attr_reader :seen
    def initialize; @seen = {}; end
    def start_element(name, attrs); @seen[:name] = name; end
    def characters(text); @seen[:text] = text; end
    def comment(text); @seen[:comment] = text; end
    def processing_instruction(target, data); @seen[:pi] = [target, data]; end
    def cdata_block(text); @seen[:cdata] = text; end
    def error(msg, line, column); @seen[:error] = msg; end
  end

  it "delivers every SAX string kind as UTF-8" do
    handler = EncodingProbeHandler.new
    Leptris::XML::SAX::Parser.new(handler).parse(<<~XML)
      <!-- café -->
      <?target données?>
      <nom-élément attr="é">crème<![CDATA[données]]></nom-élément>
    XML
    expect(handler.seen[:name].encoding).to eq(Encoding::UTF_8)
    expect(handler.seen[:name]).to eq("nom-élément")
    expect(handler.seen[:text].encoding).to eq(Encoding::UTF_8)
    expect(handler.seen[:comment].encoding).to eq(Encoding::UTF_8)
    expect(handler.seen[:pi].map(&:encoding)).to all(eq(Encoding::UTF_8))
    expect(handler.seen[:cdata].encoding).to eq(Encoding::UTF_8)
  end

  it "reuses the handler struct across parses and honors a swap" do
    first = EncodingProbeHandler.new
    parser = Leptris::XML::SAX::Parser.new(first)
    parser.parse("<a/>")
    struct_before = parser.handler_struct
    parser.parse("<a/>")
    expect(parser.handler_struct).to equal(struct_before)

    second = EncodingProbeHandler.new
    parser.document = second
    parser.parse(%(<b attr="x"/>))
    expect(parser.handler_struct).not_to equal(struct_before)
    expect(second.seen[:name]).to eq("b")
    expect(first.seen[:name]).to eq("a")
  end

  it "rejects XPath variable bindings instead of ignoring them" do
    doc = Leptris::XML.parse("<r><a/></r>")
    expect { doc.root.xpath("//a", { "x" => "1" }, { "v" => "2" }) }
      .to raise_error(ArgumentError, /variable bindings/)
    # a single trailing hash is the namespace hash (Nokogiri semantics)
    expect { doc.root.xpath("//a", { "v" => "2" }) }.not_to raise_error
    expect { doc.root.xpath("//a", { "p" => "urn:p" }, {}) }.not_to raise_error
  end

  it "raises XPathError with engine detail on failed expressions" do
    doc = Leptris::XML.parse("<r/>")
    expect { doc.root.xpath("//a[") }
      .to raise_error(Leptris::XML::XPathError)
  end

  it "unions NodeSet#xpath without duplicate container churn" do
    doc = Leptris::XML.parse("<r><a><n>1</n></a><a><n>2</n></a><b><n>3</n></b></r>")
    as = doc.root.xpath("//a")
    result = as.xpath("./n")
    expect(result.map(&:content)).to eq(%w[1 2])
  end
end
