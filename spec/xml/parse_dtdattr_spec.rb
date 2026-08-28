# frozen_string_literal: true

require "spec_helper"

# leptris/leptris#606: DTD ATTLIST default attributes apply ONLY under
# ParseOptions::DTDATTR (libxml2 XML_PARSE_DTDATTR opt-in parity). The
# default parse leaves them out — the behavior Nokogiri compares
# against, and what W3C C14N 1.1 example 3.3's canonical form assumes.
RSpec.describe "ParseOptions::DTDATTR" do
  let(:xml) do
    '<!DOCTYPE doc [<!ATTLIST e9 attr CDATA "default">]><doc><e9/></doc>'
  end

  it "excludes ATTLIST defaults by default" do
    doc = Leptris::XML::Document.parse(xml)
    e9 = doc.root.children.first
    expect(e9.attributes).to eq({})
  end

  it "applies ATTLIST defaults when the flag is set" do
    doc = Leptris::XML::Document.parse(
      xml, options: Leptris::XML::ParseOptions.dtdattr)
    e9 = doc.root.children.first
    expect(e9.attributes.keys).to eq(["attr"])
    expect(e9.attributes["attr"].value).to eq("default")
  end

  it "can be combined (noblanks | dtdattr)" do
    opts = Leptris::XML::ParseOptions.noblanks |
           Leptris::XML::ParseOptions.dtdattr
    expect(opts.dtdattr?).to be true
    expect(opts.noblanks?).to be true
    doc = Leptris::XML::Document.parse(xml, options: opts)
    expect(doc.root.children.first.attributes["attr"].value)
      .to eq("default")
  end

  it "toggles in place" do
    opts = Leptris::XML::ParseOptions.new
    expect(opts.dtdattr?).to be false
    opts.dtdattr = true
    expect(opts.dtdattr?).to be true
    opts.dtdattr = false
    expect(opts.dtdattr?).to be false
  end
end
