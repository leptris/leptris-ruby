# frozen_string_literal: true

require "spec_helper"

# XML 1.0 §2.11 end-of-line handling (leptris-ruby#326, engine
# 1.9.239): line breaks normalize to LF ON INPUT, BEFORE parsing —
# character data and CDATA sections alike — while character
# references expand AFTER normalization (a CR character reference
# stays CR: it is data, not an end-of-line). Attribute values
# collapse CRLF to ONE space (§3.3.3). libxml2/Nokogiri parity.
RSpec.describe "XML EOL normalization (engine 1.9.239)" do
  it "normalizes CRLF and lone CR in text to LF" do
    doc = Leptris::XML.parse("<a>x\r\ny\rz\nw</a>")
    expect(doc.root.content).to eq("x\ny\nz\nw")
  end

  it "keeps a CR character reference as data" do
    doc = Leptris::XML.parse("<a>x&#xD;y</a>")
    expect(doc.root.content).to eq("x\ry")
  end

  it "collapses CRLF to one space in attribute values" do
    doc = Leptris::XML.parse(%(<a att="p\r\nq\rs">t</a>))
    expect(doc.root["att"]).to eq("p q s")
  end

  it "normalizes CDATA line endings too (§2.11 is input-level)" do
    doc = Leptris::XML.parse("<a><![CDATA[x\r\ny\rz]]></a>")
    expect(doc.root.content).to eq("x\ny\nz")
  end

  it "normalizes entity-bearing runs' literal bytes only" do
    doc = Leptris::XML.parse("<a>a&amp;\r\nb</a>")
    expect(doc.root.content).to eq("a&\nb")
  end

  it "round-trips a docx-shaped fragment identically to LF-only input" do
    crlf = Leptris::XML.parse("<w:p>\r\n<w:t>Title</w:t>\r\n</w:p>")
    lf   = Leptris::XML.parse("<w:p>\n<w:t>Title</w:t>\n</w:p>")
    expect(crlf.root.to_xml).to eq(lf.root.to_xml)
  end
end
