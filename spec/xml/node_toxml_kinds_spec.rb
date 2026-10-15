# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#464 — nokogiri's Node#to_xml serializes EVERY node
# kind; code against nokogiri serializing mixed NodeSets broke with
# NoMethodError on text/comment/CDATA/PI/doctype members.
RSpec.describe "Node#to_xml on every node kind (ruby#464)" do
  let(:doc) do
    Leptris::XML.parse(
      '<r><style>a &gt; b</style><!-- note --><c><![CDATA[<raw>]]></c>' \
      "<?target pi-data?>&amp;</r>")
  end

  it "serializes text escaped" do
    text = doc.at_xpath("//style").children.first
    expect(text).to be_a(Leptris::XML::Text)
    expect(text.to_xml).to eq("a &gt; b")
  end

  it "serializes comments" do
    comment = doc.at_xpath("//r").children.find { |c| c.is_a?(Leptris::XML::Comment) }
    expect(comment.to_xml).to eq("<!-- note -->")
  end

  it "serializes CDATA wrapped" do
    cdata = doc.at_xpath("//c").children.first
    expect(cdata).to be_a(Leptris::XML::CDATA)
    expect(cdata.to_xml).to eq("<![CDATA[<raw>]]>")
  end

  it "serializes processing instructions" do
    pi = doc.at_xpath("//r").children.find do |c|
      c.is_a?(Leptris::XML::ProcessingInstruction)
    end
    expect(pi.to_xml).to eq("<?target pi-data?>")
  end

  it "serializes a mixed NodeSet (the #456 motivating shape)" do
    out = doc.root.children.to_xml
    expect(out).to include("a &gt; b")
    expect(out).to include("<!-- note -->")
    expect(out).to include("<![CDATA[<raw>]]>")
    expect(out).to include("<?target pi-data?>")
  end

  it "serializes the doctype" do
    doc2 = Leptris::XML.parse(
      "<!DOCTYPE r SYSTEM \"s.dtd\"><r/>")
    expect(doc2.doctype.to_xml).to eq("<!DOCTYPE r SYSTEM \"s.dtd\">")
  end
end
