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
