# frozen_string_literal: true

RSpec.describe Leptris::XML::Schematron do
  let(:schema_xml) do
    <<~SCH
      <schema xmlns='http://purl.oclc.org/dsdl/schematron' queryBinding='xslt'>
        <pattern>
          <rule context='item'>
            <assert test='@n &lt;= 3'>n too big</assert>
          </rule>
        </pattern>
      </schema>
    SCH
  end

  it "parses schemas and validates with failed-assert semantics" do
    sch = described_class.parse(schema_xml)

    ok = Leptris::XML::Document.parse("<r><item n='2'/></r>")
    expect(sch.valid?(ok)).to be true

    bad = Leptris::XML::Document.parse("<r><item n='9'/></r>")
    expect(sch.valid?(bad)).to be false
  end

  it "validate returns the SVRL report as a document" do
    sch = described_class.parse(schema_xml)
    bad = Leptris::XML::Document.parse("<r><item n='9'/></r>")
    svrl = sch.validate(bad)
    expect(svrl).not_to be_nil
    xml = svrl.to_s
    expect(xml).to include("svrl:schematron-output")
    expect(xml).to include("failed-assert")
    expect(xml).to include("location=\"/r/item\"")
    expect(xml).to include("n too big")
  end

  it "reports do not invalidate" do
    sch = described_class.parse(<<~SCH)
      <schema xmlns='http://purl.oclc.org/dsdl/schematron' queryBinding='xslt'>
        <pattern>
          <rule context='item'>
            <report test='@n'>has n</report>
          </rule>
        </pattern>
      </schema>
    SCH
    doc = Leptris::XML::Document.parse("<r><item n='9'/></r>")
    expect(sch.valid?(doc)).to be true
    expect(sch.validate(doc).to_s).to include("successful-report")
  end

  it "selects a phase" do
    sch = described_class.parse(<<~SCH, phase: "quick")
      <schema xmlns='http://purl.oclc.org/dsdl/schematron' queryBinding='xslt'>
        <phase id='quick'><active pattern='p1'/></phase>
        <pattern id='p1'><rule context='a'><assert test='@v'>a needs v</assert></rule></pattern>
        <pattern id='p2'><rule context='b'><assert test='@w'>b needs w</assert></rule></pattern>
      </schema>
    SCH
    doc = Leptris::XML::Document.parse("<r><a/><b/></r>")
    expect(sch.valid?(doc)).to be false
    expect(sch.validate(doc).to_s).to include("a needs v")
    expect(sch.validate(doc).to_s).not_to include("b needs w")
  end

  it "raises on schema errors with engine detail" do
    expect {
      described_class.parse(<<~SCH)
        <schema xmlns='http://purl.oclc.org/dsdl/schematron' queryBinding='xpath2'>
          <pattern><rule context='/'><assert test='true()'/></rule></pattern>
        </schema>
      SCH
    }.to raise_error(Leptris::XML::Error, /queryBinding/)
  end

  it "parses from a file" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "schema.sch")
      File.write(path, schema_xml)
      sch = described_class.parse_file(path)
      bad = Leptris::XML::Document.parse("<r><item n='9'/></r>")
      expect(sch.valid?(bad)).to be false
    end
  end
end
