# frozen_string_literal: true

require "spec_helper"

RSpec.describe "v1.6.0 surface" do
  describe Leptris::XML::XPath do
    it "compiles once and evaluates against many documents" do
      expr = described_class.compile("//i[@v > 1]")
      doc_a = Leptris::XML.parse(%(<l><i v="1"/><i v="3"/></l>))
      doc_b = Leptris::XML.parse(%(<l><i v="9"/></l>))
      expect(expr.eval(doc_a).length).to eq(1)
      expect(expr.eval(doc_b).length).to eq(1)
    end

    it "evaluates with namespace bindings" do
      expr = described_class.compile("//p:i[@v > 1]")
      doc = Leptris::XML.parse(%(<r xmlns:t="urn:x"><t:i v="2"/></r>))
      expect(expr.eval(doc, "p" => "urn:x").length).to eq(1)
      expect(expr.eval(doc, "p" => "urn:other")).to be_empty
    end

    it "evaluates from an element context node" do
      expr = described_class.compile("./i")
      doc = Leptris::XML.parse(%(<l><i v="1"/></l>))
      expect(expr.eval(doc.root).length).to eq(1)
    end

    it "raises on invalid expressions" do
      expect { described_class.compile("//i[") }
        .to raise_error(Leptris::XML::XPathError)
    end

    it "rejects non-document/element receivers" do
      expr = described_class.compile("//i")
      expect { expr.eval("not a document") }.to raise_error(ArgumentError)
    end
  end

  describe Leptris::XML::Pull do
    it "streams the full event sequence" do
      types = []
      Leptris::XML::Pull.parse(%(<r a="1"><!--c--><x>t</x></r>)) do |e|
        types << e.type
      end
      expect(types).to eq(%i[
        start_element comment start_element text end_element
        end_element end_document])
    end

    it "captures attributes on start_element events" do
      events = Leptris::XML::Pull.parse(%(<e a="1" b="two"/>)).each.to_a
      expect(events.first.attrs).to eq("a" => "1", "b" => "two")
      expect(events.first.name).to eq("e")
    end

    it "reports text, comment, and CDATA payloads" do
      events = Leptris::XML::Pull.parse(%(<r>t<!--c--><![CDATA[x]]></r>)).each.to_a
      by_type = events.each_with_object({}) { |e, h| h[e.type] ||= e.text }
      expect(by_type[:text]).to eq("t")
      expect(by_type[:comment]).to eq("c")
      expect(by_type[:cdata]).to eq("x")
    end
  end

  describe Leptris::XML::Iterparse do
    it "yields each completed top-level element" do
      names = []
      Leptris::XML::Iterparse.parse("<root><a>1</a><b>2</b></root>") do |el|
        names << [el.name, el.content]
      end
      expect(names).to eq([["a", "1"], ["b", "2"]])
    end

    it "yields elements with no parent document" do
      Leptris::XML::Iterparse.parse("<r><x/></r>") do |el|
        expect(el.document).to be_nil
      end
    end
  end

  describe "document-level PIs" do
    it "enumerates and appends" do
      doc = Leptris::XML.parse(
        %(<?xml-stylesheet href="x.xsl" type="text/xsl"?><r/>))
      expect(doc.processing_instructions)
        .to eq([["xml-stylesheet", %(href="x.xsl" type="text/xsl")]])
      doc.add_pi("custom", "v=1")
      expect(doc.processing_instructions.length).to eq(2)
    end
  end
end
