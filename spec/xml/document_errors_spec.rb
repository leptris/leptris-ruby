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

  it "is empty on a default (strict) parse failure path — raising stays" do
    expect { Leptris::XML.parse("<a><b></a>") }
      .to raise_error(Leptris::XML::ParseError)
  end
end
