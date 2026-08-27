# frozen_string_literal: true

require "spec_helper"
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


RSpec.describe "round XVII: pull hot-loop reads" do
  it "reads events through the layout-derived offsets" do
    events = []
    Leptris::XML::Pull.parse(%(<?pi data?><!-- c --><r k="v">t<b/></r>)) do |e|
      events << e
    end
    types = events.map(&:type)
    expect(types).to eq(%i[pi comment start_element text start_element
                           end_element end_element end_document])
    pi = events.first
    expect(pi.name).to eq("pi")
    expect(pi.text).to eq("data")
    expect(pi.text.encoding).to eq(Encoding::UTF_8)
    start = events.find { |e| e.type == :start_element }
    expect(start.name).to eq("r")
    expect(start.attrs).to eq({ "k" => "v" })
    expect(start.attrs.keys.first.encoding).to eq(Encoding::UTF_8)
    text = events.find { |e| e.type == :text }
    expect(text.text).to eq("t")
  end

  it "answers nil attrs when the element has none" do
    events = []
    Leptris::XML::Pull.parse(%(<r><a/></r>)) { |e| events << e }
    inner = events.find { |e| e.name == "a" }
    expect(inner.attrs).to be_nil
  end
end

RSpec.describe "libleptris 1.9.4 surface" do
  it "records events in bulk with UTF-8 strings (SAX::Recorder)" do
    kinds = []
    attrs = nil
    Leptris::XML::SAX::Recorder.parse(
      %(<r k="v">caf\xc3\xa9<!--c--></r>)) do |kind, name, text, a, _l, _c|
      kinds << kind
      attrs = a if kind == :start_element
      expect([name, text].compact.map(&:encoding)).to all(eq(Encoding::UTF_8)) if text
    end
    expect(kinds).to eq(%i[start_document start_element characters comment
                           end_element end_document])
    expect(attrs).to eq({ "k" => "v" })
  end

  it "streams recorder events from an IO chunk by chunk" do
    require "stringio"
    kinds = []
    Leptris::XML::SAX::Recorder.parse(StringIO.new(%(<r><a/><b/></r>))) do |kind, *|
      kinds << kind
    end
    expect(kinds).to eq(%i[start_document start_element start_element
                           end_element start_element end_element
                           end_element end_document])
  end

  it "iterates full-document mode in post-order (v2 #586)" do
    order = []
    Leptris::XML::Iterparse.parse(
      %(<r><a><b/></a><c/></r>), mode: :full_document) do |el|
      order << el.name
    end
    expect(order).to eq(%w[b a c r])  # child before parent
  end

  it "resolves namespaces on the last yielded element" do
    scopes = []
    iter = Leptris::XML::Iterparse.parse(
      %(<r xmlns:p="urn:p"><p:a/><q:b xmlns:q="urn:q"/></r>))
    iter.run do |el|
      scopes << [el.name, iter.namespace_uri("p"), iter.namespace_uri("nope"),
                 iter.namespace_count, iter.error]
    end
    iter.free
    # element_name is the local name (DOM-consistent); the iterator's
    # snapshot is what resolves prefixes to URIs.
    expect(scopes).to eq(
      [["a", "urn:p", nil, 1, nil],
       ["b", "urn:p", nil, 2, nil]])
    expect(iter.error).to be_nil
  end

  it "reports the error channel for truncated input" do
    it = Leptris::XML::Iterparse.parse(%(<r><a>)) { |el| }
    expect(it.error).to be_a(String)
  end
end
