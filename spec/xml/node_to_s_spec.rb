# frozen_string_literal: true

# leptris#1595: Node#to_s must serialize (Nokogiri parity) — the
# default Object#to_s object dump leaked into migrated consumers
# (coradoc math stems printed `#<Leptris::XML::Element:0x...>`).
require "spec_helper"

RSpec.describe "Node#to_s serialization parity" do
  it "serializes an element (no object dump)" do
    doc = Leptris::XML::Document.parse("<div><p>hi</p></div>")
    expect(doc.root.to_s).to eq(doc.root.to_xml)
    expect(doc.root.to_s).to include("<p>hi</p>")
    expect(doc.root.to_s).not_to match(/0x[0-9a-f]+>/)
  end

  it "serializes a nested element" do
    doc = Leptris::XML::Document.parse("<r><a><b/></a></r>")
    expect(doc.root.at("a").to_s).to eq(doc.root.at("a").to_xml)
  end

  it "serializes a document" do
    doc = Leptris::XML::Document.parse("<root><child/></root>")
    expect(doc.to_s).to eq(doc.to_xml)
    expect(doc.to_s).to include("<child/>")
  end

  it "HTML-parsed documents serialize through to_s" do
    doc = Leptris::HTML.parse("<div><p>hi</p></div>")
    node = doc.root.at("div")
    expect(node.to_s).to eq(node.to_xml)
    expect(node.to_s).to include("<p>hi</p>")
  end
end

  # #1595 follow-up: the #403 fix covered Element/Document — the
  # leaf node types (Text, Comment, CDATA, PI) still fell back to
  # Object#to_s object dumps. Nokogiri's Node#to_s serializes
  # EVERY node type.
  RSpec.describe "Node#to_s leaf types" do
    let(:doc) do
      Leptris::XML::Document.parse(
        "<r><!--c-->t<ct><![CDATA[data]]></ct><?pi instr?></r>")
    end

    it "serializes text" do
      text = doc.at("r").children.find { |n| n.is_a?(Leptris::XML::Text) }
      expect(text.to_s).to eq("t")
      expect(text.to_s).not_to match(/0x[0-9a-f]+>/)
    end

    it "serializes comments" do
      comment = doc.at("r").children.find { |n| n.is_a?(Leptris::XML::Comment) }
      expect(comment.to_s).to eq("<!--c-->")
      expect(comment.to_s).not_to match(/0x[0-9a-f]+>/)
    end

    it "serializes CDATA" do
      cdata = doc.at("ct").children.find { |n| n.is_a?(Leptris::XML::CDATA) }
      expect(cdata.to_s).to include("data")
      expect(cdata.to_s).not_to match(/0x[0-9a-f]+>/)
    end

    it "serializes processing instructions" do
      pi = doc.at("r").children.find do |n|
        n.is_a?(Leptris::XML::ProcessingInstruction)
      end
      expect(pi.to_s).to eq("<?pi instr?>")
      expect(pi.to_s).not_to match(/0x[0-9a-f]+>/)
    end
  end
