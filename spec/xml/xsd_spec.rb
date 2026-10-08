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

# libleptris 1.9.319 (#1075 slice 2): lexical validation — the
# tier-1 built-in table and user simpleTypes through
# cycle-guarded restriction chains. Tri-state at the C face maps
# to true/false with a raise on the unknown-name -1 (a silent
# false would let misspelled types validate nothing forever).
RSpec.describe "XSD lexical validation (1.9.319 slice 2)" do
  describe ".builtin_valid?" do
    it "validates the built-in table by reference spelling" do
      expect(Leptris::XML::XSD.builtin_valid?("xs:token", "ABC")).to be(true)
      expect(Leptris::XML::XSD.builtin_valid?("xs:token", "a b")).to be(true)
      expect(Leptris::XML::XSD.builtin_valid?("xs:boolean", "1")).to be(true)
      expect(Leptris::XML::XSD.builtin_valid?("xs:boolean", "maybe")).to be(false)
      expect(Leptris::XML::XSD.builtin_valid?("xs:int", "-42")).to be(true)
      expect(Leptris::XML::XSD.builtin_valid?("xs:date", "2026-13-40")).to be(false)
    end

    it "raises on names outside the tier-1 table" do
      expect { Leptris::XML::XSD.builtin_valid?("xs:nonsense", "x") }
        .to raise_error(ArgumentError, /not in the tier-1 built-in table/)
    end
  end

  describe "#simple_valid?" do
    let(:schema) do
      Leptris::XML::XSD.compile(<<~XSD)
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="code">
            <xs:restriction base="xs:token">
              <xs:pattern value="[A-Z]{3}"/>
            </xs:restriction>
          </xs:simpleType>
          <xs:simpleType name="level">
            <xs:restriction base="xs:string">
              <xs:enumeration value="low"/>
              <xs:enumeration value="high"/>
            </xs:restriction>
          </xs:simpleType>
        </xs:schema>
      XSD
    end

    it "validates pattern and enumeration facets" do
      expect(schema.simple_valid?("code", "ABC")).to be(true)
      expect(schema.simple_valid?("code", "ABCD")).to be(false)
      expect(schema.simple_valid?("level", "low")).to be(true)
      expect(schema.simple_valid?("level", "mid")).to be(false)
    end

    it "raises on unknown type names" do
      expect { schema.simple_valid?("nope", "x") }
        .to raise_error(ArgumentError, /not a simpleType/)
    end
  end
end

# libleptris 1.9.321 (#1075 slices 3-4): content models through a
# Thompson NFA and whole-instance validation with enumerated
# failures. The inline-anonymous complexType capture gap is filed
# upstream (leptris#1592) — these pins use the named-ref shape,
# which captures and validates end to end.
RSpec.describe "XSD instance validation (1.9.321 slices 3-4)" do
  let(:schema) do
    Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="bookType">
          <xs:sequence>
            <xs:element name="title" type="xs:date"/>
            <xs:element name="author" type="xs:token"/>
          </xs:sequence>
          <xs:attribute name="lang" type="xs:token" use="required"/>
        </xs:complexType>
        <xs:element name="book" type="bookType"/>
      </xs:schema>
    XSD
  end

  it "accepts a valid instance" do
    doc = Leptris::XML::Document.parse(
      %(<book lang="en"><title>2026-01-02</title><author>A</author></book>))
    expect(schema.valid?(doc)).to be(true)
    expect(schema.validate_errors(doc)).to be_empty
  end

  it "enumerates lexical failures with element context" do
    doc = Leptris::XML::Document.parse(
      %(<book lang="en"><title>not-a-date</title><author>A</author></book>))
    expect(schema.valid?(doc)).to be(false)
    errors = schema.validate_errors(doc)
    expect(errors).not_to be_empty
    expect(errors.first).to include("title")
  end

  it "checks required attributes" do
    doc = Leptris::XML::Document.parse(
      %(<book><title>2026-01-02</title><author>A</author></book>))
    expect(schema.valid?(doc)).to be(false)
  end

  it "orders content through the NFA (content_valid?)" do
    kids = Leptris::XML::Document.parse(
      %(<b><title>2026-01-02</title><author>x</author></b>)).root.element_children
    expect(schema.content_valid?("book", kids)).to be(true)
    swapped = Leptris::XML::Document.parse(
      %(<b><author>x</author><title>2026-01-02</title></b>)).root.element_children
    expect(schema.content_valid?("book", swapped)).to be(false)
  end

  it "raises on unknown element declarations (the -1 contract)" do
    kids = Leptris::XML::Document.parse(%(<b><title>2026-01-02</title></b>))
      .root.element_children
    expect { schema.content_valid?("nope", kids) }
      .to raise_error(ArgumentError, /not a top-level element/)
  end
end
