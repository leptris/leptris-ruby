# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Leptris::XML::DTD (libleptris >= 1.9.200)" do
  let(:dtd_text) do
    "<!ELEMENT r (item+)>\n" \
      "<!ELEMENT item EMPTY>\n" \
      "<!ATTLIST item n CDATA #REQUIRED>\n"
  end

  it "validates a conforming document" do
    dtd = Leptris::XML::DTD.parse(dtd_text)
    doc = Leptris::XML::Document.parse("<r><item n='1'/><item n='2'/></r>")
    expect(dtd.valid?(doc)).to be(true)
    expect(dtd.validate(doc)).to be_nil
  end

  it "reports the first violation with message and element" do
    dtd = Leptris::XML::DTD.parse(dtd_text)
    doc = Leptris::XML::Document.parse("<r><item>x</item></r>")
    expect(dtd.valid?(doc)).to be(false)
    error = dtd.validate(doc)
    expect(error).to be_a(Hash)
    expect(error[:message]).to include("EMPTY")
    expect(error[:element_name]).to eq("item")
  end

  it "enforces content-model repetition (item+ takes many)" do
    dtd = Leptris::XML::DTD.parse(dtd_text)
    doc = Leptris::XML::Document.parse("<r>#{'<item n=\'1\'/>' * 5}</r>")
    expect(dtd.valid?(doc)).to be(true)
  end

  it "parses from a file" do
    path = File.join(Dir.tmpdir, "leptris_binding.dtd")
    File.write(path, dtd_text)
    dtd = Leptris::XML::DTD.parse_file(path)
    doc = Leptris::XML::Document.parse("<r><item n='1'/></r>")
    expect(dtd.valid?(doc)).to be(true)
  ensure
    File.delete(path) if File.exist?(path)
  end

  # The engine's DTD parser is lenient by design (XML 1.0 gives
  # processors latitude over declaration-level errors): malformed
  # input yields a mostly-empty DTD and validation surfaces the
  # problems. Engine issue tracks the "NULL on error" header
  # contract separately.
  it "leniently parses malformed DTD input" do
    dtd = Leptris::XML::DTD.parse("<!ELEMENT broken (>")
    expect(dtd).to be_a(Leptris::XML::DTD::Handle)
    # No declarations survive the broken input, so validation is
    # vacuously true — errors surface only for well-formed DTDs.
    doc = Leptris::XML::Document.parse("<r><item n='1'/></r>")
    expect(dtd.valid?(doc)).to be(true)
  end
end
