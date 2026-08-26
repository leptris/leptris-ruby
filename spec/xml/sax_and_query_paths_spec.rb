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

