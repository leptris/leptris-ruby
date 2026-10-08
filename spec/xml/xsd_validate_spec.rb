# frozen_string_literal: true

require "spec_helper"

# XSD slices 3-4 (libleptris >= 1.9.321, #1075): instance
# validation with accumulated errors, and content-model checks.
# Tier-1 scope: top-level elements must carry BOTH name and type
# attributes (the inline anonymous complexType shape compiles but
# its element is not tracked yet — content/validate stay lax about
# it), and validation descends exactly one level (children are
# checked against the content model; grandchildren are not).
RSpec.describe "Leptris::XML::XSD instance validation" do
  face = proc { Leptris::XML::FFI.respond_to?(:leptris_xsd_validate) }

  let(:schema_text) do
    <<~XSD
      <?xml version="1.0"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="note" type="t_note"/>
        <xs:complexType name="t_note">
          <xs:sequence>
            <xs:element name="to" type="xs:string"/>
            <xs:element name="urgency" type="xs:integer"/>
          </xs:sequence>
        </xs:complexType>
      </xs:schema>
    XSD
  end

  before { skip "requires the libleptris 1.9.321 validation faces" unless face.call }

  it "accepts a structurally valid document" do
    schema = Leptris::XML::XSD.compile(schema_text)
    doc = Leptris::XML::Document.parse(
      "<note><to>You</to><urgency>3</urgency></note>")
    expect(schema.valid?(doc)).to be(true)
    expect(schema.validate(doc)).to eq([])
  end

  it "reports a missing sequence member" do
    schema = Leptris::XML::XSD.compile(schema_text)
    doc = Leptris::XML::Document.parse("<note><urgency>3</urgency></note>")
    errors = schema.validate(doc)
    expect(errors).not_to be_empty
  end

  it "reports child-order violations" do
    schema = Leptris::XML::XSD.compile(schema_text)
    doc = Leptris::XML::Document.parse(
      "<note><urgency>3</urgency><to>You</to></note>")
    expect(schema.validate(doc)).not_to be_empty
  end

  it "checks an element's content model directly" do
    schema = Leptris::XML::XSD.compile(schema_text)
    expect(schema.content_valid?("note", %w[to urgency])).to be(true)
    expect(schema.content_valid?("note", %w[urgency to])).to be(false)
    expect {
      schema.content_valid?("nope", %w[to])
    }.to raise_error(ArgumentError)
  end

  it "is lax about the anonymous-complexType shape (tier-1 scope)" do
    pending "engine slice 4 tracks named+typed elements only"
    schema = Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="note">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="to" type="xs:string"/>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
    doc = Leptris::XML::Document.parse("<note><wrong/></note>")
    expect(schema.validate(doc)).not_to be_empty
  end
end
