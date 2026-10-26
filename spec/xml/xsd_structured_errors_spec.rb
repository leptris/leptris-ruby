# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Leptris::XML::XSD::Schema#structured_errors",
               if: defined?(Leptris::XML::XSD) &&
                   Leptris::XML::XSD.respond_to?(:compile) &&
                   Leptris::XML::FFI.respond_to?(:leptris_xsd_error_report) do
  let(:schema) do
    Leptris::XML::XSD.compile(
      '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">' \
      '<xs:element name="note">' \
      '<xs:complexType>' \
      '<xs:sequence>' \
      '<xs:element name="to" type="xs:string"/>' \
      '</xs:sequence>' \
      '<xs:attribute name="id" type="xs:integer" use="required"/>' \
      '</xs:complexType>' \
      '</xs:element></xs:schema>'
    )
  end

  it "returns rows with kind, component, position, message" do
    doc = Leptris::XML::Document.parse(
      "<note id=\"abc\"><from>x</from></note>"
    )
    rows = schema.structured_errors(doc)
    expect(rows.size).to eq(2)
    kinds = rows.map(&:kind)
    expect(kinds).to contain_exactly("attribute-use", "content-model")
    attr_row = rows.find { |r| r.kind == "attribute-use" }
    expect(attr_row.component).to eq("id")
    expect(attr_row.line).to eq(1)
    expect(attr_row.column).to be > 0
    expect(attr_row.message).to include("attribute 'id'")
    model_row = rows.find { |r| r.kind == "content-model" }
    expect(model_row.component).to eq("note")
  end

  it "returns an empty list for a valid document" do
    doc = Leptris::XML::Document.parse("<note id=\"3\"><to>x</to></note>")
    expect(schema.structured_errors(doc)).to eq([])
  end
end
