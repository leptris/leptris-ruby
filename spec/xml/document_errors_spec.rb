# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#465 — the recover lane's nokogiri parity surface:
# recovered parses expose their diagnostics as doc.errors entries.
RSpec.describe "Document#errors (ruby#465)" do
  it "returns [] for a clean parse" do
    doc = Leptris::XML.parse("<r><a/></r>", recover: true)
    expect(doc.errors).to eq([])
  end

  it "returns SyntaxError entries for a recovered parse" do
    doc = Leptris::XML.parse("<a><b></a>", recover: true)
    expect(doc.root.name).to eq("a")
    expect(doc.errors).not_to be_empty
    expect(doc.errors.first).to be_a(Leptris::XML::SyntaxError)
    expect(doc.errors.first.message).not_to be_empty
  end

  it "errors face is irrelevant on the strict opt-in — raising stays" do
    expect { Leptris::XML.parse("<a><b></a>", strict: true) }
      .to raise_error(Leptris::XML::ParseError)
  end
end

RSpec.describe "recover-by-default (leptris-ruby#478 / moxml parity)" do
  it "parse() recovers malformed input like nokogiri, exposing doc.errors" do
    doc = Leptris::XML.parse("<a><b></a>")
    expect(doc.root.name).to eq("a")
    expect(doc.errors).not_to be_empty
  end

  it "clean documents parse identically under the default" do
    doc = Leptris::XML.parse("<r><a x='1'>t</a></r>")
    expect(doc.root.to_xml).to eq("<r><a x=\"1\">t</a></r>")
    expect(doc.errors).to be_empty
  end
end
