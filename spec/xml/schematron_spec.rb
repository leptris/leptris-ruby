# frozen_string_literal: true

# The Schematron face (leptris-ruby#676 audit): parse once —
# optionally selecting a PHASE, which activates only its patterns —
# then validate any number of documents. #valid? answers the
# boolean; #validate returns the SVRL report as a queryable
# Document. Requires libleptris >= 1.9.126.
SCH = '<schema xmlns="http://purl.oclc.org/dsdl/schematron"><pattern>' \
      '<rule context="item"><assert test="@id">item needs id</assert>' \
      '</rule></pattern></schema>'

RSpec.describe "Leptris::XML::Schematron (libleptris 1.9.144 family)" do
  it "validates and answers valid? both ways" do
    sch = Leptris::XML::Schematron.parse(SCH)
    expect(sch.valid?(Leptris::XML::Document.parse("<r><item id='1'/></r>"))).to be(true)
    expect(sch.valid?(Leptris::XML::Document.parse("<r><item/></r>"))).to be(false)
  end

  it "returns the SVRL report as a queryable Document" do
    sch = Leptris::XML::Schematron.parse(SCH)
    svrl = sch.validate(Leptris::XML::Document.parse("<r><item/></r>"))
    expect(svrl).to be_a(Leptris::XML::Document)
    expect(svrl.at_xpath("//*[local-name()='failed-assert']")).not_to be_nil
  end

  it "selects a phase — only its patterns activate" do
    sch = Leptris::XML::Schematron.parse(<<~SCH, phase: "quick")
      <schema xmlns='http://purl.oclc.org/dsdl/schematron'>
        <phase id='quick'><active pattern='p1'/></phase>
        <pattern id='p1'><rule context='a'><assert test='@v'>a needs v</assert></rule></pattern>
        <pattern id='p2'><rule context='b'><assert test='@w'>b needs w</assert></rule></pattern>
      </schema>
    SCH
    doc = Leptris::XML::Document.parse("<r><a/><b/></r>")
    expect(sch.valid?(doc)).to be(false)
    expect(sch.validate(doc).to_s).to include("a needs v")
    expect(sch.validate(doc).to_s).not_to include("b needs w")
  end

  it "successful reports do not invalidate" do
    sch = Leptris::XML::Schematron.parse(
      "<schema xmlns='http://purl.oclc.org/dsdl/schematron'>" \
      "<pattern><rule context='item'><report test='@id'>item has id</report></rule></pattern></schema>"
    )
    doc = Leptris::XML::Document.parse("<r><item id='1'/></r>")
    expect(sch.valid?(doc)).to be(true)
    expect(sch.validate(doc).to_s).to include("item has id")
  end

  it "parses from a file" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "schema.sch")
      File.write(path, SCH)
      sch = Leptris::XML::Schematron.parse_file(path)
      expect(sch.valid?(Leptris::XML::Document.parse("<r><item id='1'/></r>"))).to be(true)
      expect(sch.valid?(Leptris::XML::Document.parse("<r><item/></r>"))).to be(false)
    end
  end
end
