# frozen_string_literal: true

require "spec_helper"

# XSD tier-1 (libleptris >= 1.9.318, #1075): the compilation
# surface — compile, declaration census, schema-level errors.
RSpec.describe "Leptris::XML::XSD (tier-1)" do
  let(:schema_text) do
    <<~XSD
      <?xml version="1.0"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="note">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="to" type="xs:string"/>
              <xs:element name="from" type="xs:string"/>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
        <xs:element name="blank" type="xs:string"/>
      </xs:schema>
    XSD
  end

  it "compiles a schema and counts its declarations" do
    pending "requires the libleptris 1.9.318 XSD face" unless
      Leptris::XML::FFI.respond_to?(:leptris_xsd_compile)

    schema = Leptris::XML::XSD.compile(schema_text)
    expect(schema.declaration_count).to be >= 2
    expect(schema.error).to be_nil
  end

  it "compiles a schema-level problem to an error message" do
    pending "requires the libleptris 1.9.318 XSD face" unless
      Leptris::XML::FFI.respond_to?(:leptris_xsd_compile)

    schema = Leptris::XML::XSD.compile("<not-a-schema/>")
    expect(schema.error).to be_a(String)
  end

  it "raises on text that is not XML at all" do
    pending "requires the libleptris 1.9.318 XSD face" unless
      Leptris::XML::FFI.respond_to?(:leptris_xsd_compile)

    expect { Leptris::XML::XSD.compile("") }
      .to raise_error(Leptris::XML::Error)
  end
end
