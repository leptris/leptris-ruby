# frozen_string_literal: true

require "tmpdir"

RSpec.describe Leptris::XML::RelaxNG do
  let(:schema_xml) do
    <<~RNG
      <grammar xmlns='http://relaxng.org/ns/structure/1.0'>
        <start>
          <element name='book'>
            <attribute name='id'/>
            <oneOrMore><element name='author'><text/></element></oneOrMore>
          </element>
        </start>
      </grammar>
    RNG
  end

  it "parses schemas and validates documents with Jing verdict parity" do
    rng = described_class.parse(schema_xml)

    ok = Leptris::XML::Document.parse(
      "<book id='b1'><author>A</author><author>B</author></book>")
    expect(rng.valid?(ok)).to be true
    expect(rng.validate(ok)).to eq([])

    bad = Leptris::XML::Document.parse("<book><author>A</author></book>")
    expect(rng.valid?(bad)).to be false
    errors = rng.validate(bad)
    expect(errors.length).to eq(1)
    expect(errors.first).to match(/\A\d+:\d+: error: /)
    expect(errors.first).to include("attribute")
  end

  it "parses schema files and resolves <include> relative to them" do
    Dir.mktmpdir do |dir|
      rng_ns = "http://relaxng.org/ns/structure/1.0"
      File.write(File.join(dir, "lib.rng"),
        "<grammar xmlns='#{rng_ns}'>" \
          "<define name='content'><element name='e'><empty/></element></define>" \
          "</grammar>")
      main = File.join(dir, "main.rng")
      File.write(main,
        "<grammar xmlns='#{rng_ns}'>" \
          "<include href='lib.rng'/>" \
          "<start><ref name='content'/></start>" \
          "</grammar>")

      rng = described_class.parse_file(main)
      expect(rng.valid?(Leptris::XML::Document.parse("<e/>"))).to be true
      expect(rng.valid?(Leptris::XML::Document.parse("<x/>"))).to be false
    end
  end

  it "enforces data facets" do
    rng = described_class.parse(
      "<grammar xmlns='http://relaxng.org/ns/structure/1.0'>" \
        "<start><element name='n'>" \
          "<data type='integer'>" \
            "<param name='minInclusive'>5</param>" \
          "</data>" \
        "</element></start></grammar>")
    expect(rng.valid?(Leptris::XML::Document.parse("<n>7</n>"))).to be true
    expect(rng.valid?(Leptris::XML::Document.parse("<n>3</n>"))).to be false
  end

  it "raises with detail on schema errors" do
    expect {
      described_class.parse(
        "<grammar xmlns='http://relaxng.org/ns/structure/1.0'>" \
        "<start><element name='e'><bogus/></element></start></grammar>")
    }.to raise_error(Leptris::XML::Error, /unknown pattern/)
  end

  it "raises on missing schema files" do
    expect {
      described_class.parse_file("/nonexistent/spec.rng")
    }.to raise_error(Leptris::XML::Error, /cannot open/)
  end
end
