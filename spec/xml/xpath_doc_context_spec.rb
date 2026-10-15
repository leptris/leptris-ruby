# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#458 — document-level XPath evaluates against the
# DOCUMENT node (libxml2/nokogiri semantics), and the //* fast path
# continues past predicates. Needs libleptris 1.9.358.
RSpec.describe "document-level XPath attribute terminals (ruby#458)" do
  let(:doc) { Leptris::XML.parse('<r><a id="x"><b/></a></r>') }

  it "resolves relative attribute-terminal paths" do
    expect(doc.xpath("r/a/@id").first&.value).to eq("x")
  end

  it "resolves filter-expr attribute terminals" do
    expect(doc.xpath("//*[local-name()='a']/@id").first&.value).to eq("x")
  end

  it "resolves descendant axes from document level (VM doc-node walk)" do
    expect(doc.xpath(".//a").size).to eq(1)
    expect(doc.xpath("descendant::a").size).to eq(1)
  end

  it "keeps the leading-// shapes working" do
    expect(doc.xpath("//a/@id").first&.value).to eq("x")
    expect(doc.xpath("//@id").first&.value).to eq("x")
  end

  it "matches the root for bare relative names and *" do
    expect(doc.xpath("r").size).to eq(1)
    expect(doc.xpath("*").size).to eq(1)
    expect(doc.xpath("a").size).to eq(0)
  end

  it "keeps ./@id empty at document level" do
    expect(doc.xpath("./@id").size).to eq(0)
  end
end
