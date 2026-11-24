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
    expect(rng.validate_errors(ok)).to eq([])

    bad = Leptris::XML::Document.parse("<book><author>A</author></book>")
    expect(rng.valid?(bad)).to be false
    errors = rng.validate(bad)
    expect(errors.length).to eq(1)
    expect(errors.first).to match(/\A\d+:\d+: error: /)
    expect(errors.first).to include("attribute")

    structured = rng.validate_errors(bad)
    expect(structured.length).to eq(1)
    expect(structured.first.keys).to contain_exactly(:line, :column, :message)
    expect(structured.first[:line]).to be_an(Integer)
    expect(structured.first[:column]).to be_an(Integer)
    expect(structured.first[:message]).to include("attribute")

    # validate renders its strings from the same rows
    rendered = structured.map do |e|
      e[:line] > 0 ? "#{e[:line]}:#{e[:column]}: error: #{e[:message]}"
                    : e[:message]
    end
    expect(rng.validate(bad)).to eq(rendered)
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

# The Schematron examples live in schematron_spec.rb (MECE: one
# face, one spec file).

# libleptris 1.9.319: the regex engine's {n} EXACT quantifiers
# parsed open-ended — [A-Z]{3} matched ABCD. Any schema using
# exact bounds silently over-accepted; never-again pin through
# the binding's datatype path.
RSpec.describe "RELAX NG exact {n} quantifiers (1.9.319)" do
  let(:schema) do
    Leptris::XML::RelaxNG.parse(<<~RNG)
      <element name="code" xmlns="http://relaxng.org/ns/structure/1.0"
               datatypeLibrary="http://www.w3.org/2001/XMLSchema-datatypes">
        <data type="token">
          <param name="pattern">[A-Z]{3}</param>
        </data>
      </element>
    RNG
  end

  it "accepts exactly-n runs" do
    expect(schema.valid?(Leptris::XML::Document.parse(%(<code>ABC</code>)))).to be(true)
  end

  it "rejects longer runs" do
    expect(schema.valid?(Leptris::XML::Document.parse(%(<code>ABCD</code>)))).to be(false)
  end
end

# ruby#650 / leptris#2093: libleptris 1.9.428 (leptris#2088) wraps each
# combine body in a group — correct per RELAX NG §4.17 — but its
# validator matched an interleave branch as one contiguous run, so an
# element of the combined-in body could not go between the members of
# the base sequence (the relaton BibDataExtensionType shape). Fixed in
# 1.9.429 (leptris#2094); never-again pin through the include path.
RSpec.describe "RELAX NG combine=\"interleave\" into a base sequence (ruby#650)" do
  rng_ns = "http://relaxng.org/ns/structure/1.0"

  around do |example|
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "base.rng"), <<~RNG)
        <grammar xmlns="#{rng_ns}">
          <start><element name="ext"><ref name="Ext"/></element></start>
          <define name="Ext">
            <element name="doctype"><text/></element>
            <element name="flavor"><text/></element>
            <zeroOrMore><element name="ics"><text/></element></zeroOrMore>
          </define>
        </grammar>
      RNG
      @ext = File.join(dir, "ext.rng")
      File.write(@ext, <<~RNG)
        <grammar xmlns="#{rng_ns}">
          <include href="base.rng"/>
          <define name="Ext" combine="interleave">
            <optional><element name="price-code"><text/></element></optional>
          </define>
        </grammar>
      RNG
      example.run
    end
  end

  let(:schema) { Leptris::XML::RelaxNG.parse_file(@ext) }

  def errors_for(body)
    schema.validate_errors(Leptris::XML::Document.parse("<ext>#{body}</ext>"))
  end

  it "accepts the base sequence alone" do
    expect(errors_for("<doctype>a</doctype><flavor>b</flavor><ics>c</ics>"))
      .to eq([])
  end

  it "accepts the added element after the base sequence" do
    expect(errors_for("<doctype>a</doctype><flavor>b</flavor><ics>c</ics>" \
                      "<price-code>d</price-code>")).to eq([])
  end

  it "accepts the added element before the base sequence" do
    expect(errors_for("<price-code>d</price-code><doctype>a</doctype>" \
                      "<flavor>b</flavor><ics>c</ics>")).to eq([])
  end

  it "accepts the added element in the middle of the base sequence" do
    expect(errors_for("<doctype>a</doctype><flavor>b</flavor>" \
                      "<price-code>d</price-code><ics>c</ics>")).to eq([])
  end

  it "accepts the added element between the required base members" do
    expect(errors_for("<doctype>a</doctype><price-code>d</price-code>" \
                      "<flavor>b</flavor><ics>c</ics>")).to eq([])
  end

  it "keeps the base sequence order" do
    expect(errors_for("<flavor>b</flavor><doctype>a</doctype><ics>c</ics>"))
      .not_to be_empty
  end
end
