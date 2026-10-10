# frozen_string_literal: true

require "tmpdir"
require "fileutils"
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

# libleptris 1.9.323 (#1592): inline ANONYMOUS complexType/
# simpleType capture — the most common XSD spelling previously
# got no content model (validation silently skipped the content
# check; content_valid? answered -1). Inline types capture under
# a synthesized element:NAME slot now.
RSpec.describe "XSD inline anonymous type capture (1.9.323, #1592)" do
  let(:schema) do
    Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="book">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="title" type="xs:token"/>
              <xs:element name="author" type="xs:token"
                          minOccurs="1" maxOccurs="unbounded"/>
            </xs:sequence>
            <xs:attribute name="lang" type="xs:token" use="required"/>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
  end

  it "enforces the content model of inline anonymous types" do
    good = Leptris::XML::Document.parse(
      %(<book lang="en"><title>T</title><author>A</author></book>))
    expect(schema.valid?(good)).to be(true)

    bad = Leptris::XML::Document.parse(
      %(<book lang="en"><author>A</author><author>B</author><isbn>9</isbn></book>))
    expect(schema.valid?(bad)).to be(false)
    expect(schema.validate_errors(bad)).to include(/content model/)
  end

  it "answers content_valid? for inline anonymous declarations" do
    kids = Leptris::XML::Document.parse(
      %(<b><title>t</title><author>x</author></b>)).root.element_children
    expect(schema.content_valid?("book", kids)).to be(true)
    swapped = Leptris::XML::Document.parse(
      %(<b><author>x</author><title>t</title></b>)).root.element_children
    expect(schema.content_valid?("book", swapped)).to be(false)
  end

  it "types anonymous simpleType particles' text" do
    simple = Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="code">
          <xs:simpleType>
            <xs:restriction base="xs:token">
              <xs:pattern value="[A-Z]{3}"/>
            </xs:restriction>
          </xs:simpleType>
        </xs:element>
      </xs:schema>
    XSD
    expect(simple.valid?(Leptris::XML::Document.parse(%(<code>ABC</code>)))).to be(true)
    expect(simple.valid?(Leptris::XML::Document.parse(%(<code>ABCD</code>)))).to be(false)
  end
end

# libleptris 1.9.324 (#1075): identity constraints — xs:key /
# xs:unique / xs:keyref on top-level declarations, two-pass
# validation driven by the engine's XPath. Tier-1 complete:
# compile -> datatypes/facets -> content models -> instance
# validation -> identity constraints.
RSpec.describe "XSD identity constraints (1.9.324)" do
  let(:schema) do
    Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="lib">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="book" maxOccurs="unbounded">
                <xs:complexType>
                  <xs:attribute name="id" type="xs:token" use="required"/>
                  <xs:attribute name="ref" type="xs:token"/>
                </xs:complexType>
              </xs:element>
            </xs:sequence>
          </xs:complexType>
          <xs:key name="bookKey">
            <xs:selector xpath="book"/>
            <xs:field xpath="@id"/>
          </xs:key>
          <xs:keyref name="bookRef" refer="bookKey">
            <xs:selector xpath="book"/>
            <xs:field xpath="@ref"/>
          </xs:keyref>
        </xs:element>
      </xs:schema>
    XSD
  end

  it "accepts resolved keyrefs" do
    doc = Leptris::XML::Document.parse(
      %(<lib><book id="a" ref="b"/><book id="b"/></lib>))
    expect(schema.valid?(doc)).to be(true)
    expect(schema.validate_errors(doc)).to be_empty
  end

  it "rejects duplicate key tuples" do
    doc = Leptris::XML::Document.parse(
      %(<lib><book id="a"/><book id="a"/></lib>))
    expect(schema.valid?(doc)).to be(false)
    expect(schema.validate_errors(doc)).to include(/duplicate key tuple/)
  end

  it "rejects dangling keyrefs" do
    doc = Leptris::XML::Document.parse(
      %(<lib><book id="a" ref="zzz"/></lib>))
    expect(schema.valid?(doc)).to be(false)
    expect(schema.validate_errors(doc))
      .to include(/reference does not resolve to any key/)
  end

  it "requires non-empty key fields" do
    doc = Leptris::XML::Document.parse(
      %(<lib><book/><book id="b"/></lib>))
    expect(schema.valid?(doc)).to be(false)
    expect(schema.validate_errors(doc))
      .to include(/missing a field value/)
  end
end

# libleptris 1.9.325: a child declared only as a PARTICLE of its
# parent's content model (no global xs:element) is governed by
# the parent's particle declaration — attribute types included.
# Previously such children skipped attribute/content checks.
RSpec.describe "XSD local particle governance (1.9.325)" do
  it "validates particle-only children's attributes" do
    schema = Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="order">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="item" maxOccurs="unbounded">
                <xs:complexType>
                  <xs:attribute name="qty" type="xs:integer" use="required"/>
                </xs:complexType>
              </xs:element>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
    expect(schema.valid?(Leptris::XML::Document.parse(%(<order><item qty="7"/></order>)))).to be(true)
    expect(schema.valid?(Leptris::XML::Document.parse(%(<order><item qty="nan"/></order>)))).to be(false)
  end
end

# libleptris 1.9.326: charter completion — unions, lists.
# KNOWN GAP (leptris#1615): memberTypes + inline anonymous member
# together over-accepts; these pins use each spelling alone,
# which is correct on both the lexical and instance paths.
RSpec.describe "XSD unions and lists (1.9.326)" do
  let(:schema) do
    Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:simpleType name="intOrAuto">
          <xs:union>
            <xs:simpleType><xs:restriction base="xs:integer"/></xs:simpleType>
            <xs:simpleType>
              <xs:restriction base="xs:token">
                <xs:enumeration value="auto"/>
              </xs:restriction>
            </xs:simpleType>
          </xs:union>
        </xs:simpleType>
        <xs:element name="v" type="intOrAuto"/>
        <xs:simpleType name="ints">
          <xs:list itemType="xs:integer"/>
        </xs:simpleType>
        <xs:element name="list" type="ints"/>
      </xs:schema>
    XSD
  end

  it "unions accept any member — lexical and instance" do
    expect(Leptris::XML::XSD.builtin_valid?("xs:integer", "42")).to be(true)
    expect(schema.simple_valid?("intOrAuto", "42")).to be(true)
    expect(schema.simple_valid?("intOrAuto", "auto")).to be(true)
    expect(schema.simple_valid?("intOrAuto", "zz")).to be(false)
    expect(schema.valid?(Leptris::XML::Document.parse(%(<v>auto</v>)))).to be(true)
    expect(schema.valid?(Leptris::XML::Document.parse(%(<v>zz</v>)))).to be(false)
  end

  it "lists type every item" do
    expect(schema.simple_valid?("ints", "1 2 3")).to be(true)
    expect(schema.simple_valid?("ints", "1 x 3")).to be(false)
    expect(schema.valid?(Leptris::XML::Document.parse(%(<list>1 2 3</list>)))).to be(true)
    expect(schema.valid?(Leptris::XML::Document.parse(%(<list>1 x 3</list>)))).to be(false)
  end
end

# libleptris 1.9.331: a duplicate <!DOCTYPE keeps the FIRST
# model (keep-first, matching the duplicate-attribute rule) —
# the first internal subset's entities apply.
RSpec.describe "duplicate DOCTYPE keeps the first model (1.9.331)" do
  it "resolves entities from the first internal subset" do
    doc = Leptris::XML::Document.parse(
      %(<!DOCTYPE r [<!ENTITY x "first">]>) +
      %(<!DOCTYPE r [<!ENTITY x "second">]>) +
      %(<r>&x;</r>), recover: true)
    expect(doc.root.content).to eq("first")
  end
end

# libleptris 1.9.332-1.9.334: XSD 1.1 tier 2 + the completion
# wave. Also pins the #1615 outcome: the WELL-FORMED mixed union
# (memberTypes + inline member) validates correctly on both
# paths, and a MALFORMED schema compiles to an error-carrying
# handle that fails validation closed.
RSpec.describe "XSD 1.1 and completion wave (1.9.332-334)" do
  it "evaluates xs:assert on complexTypes (1.1)" do
    schema = Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 version="1.1">
        <xs:element name="order">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="start" type="xs:integer"/>
              <xs:element name="end" type="xs:integer"/>
            </xs:sequence>
            <xs:assert test="xs:integer(end) gt xs:integer(start)"/>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
    expect(schema.valid?(Leptris::XML::Document.parse(
      %(<order><start>1</start><end>9</end></order>)))).to be(true)
    expect(schema.valid?(Leptris::XML::Document.parse(
      %(<order><start>9</start><end>1</end></order>)))).to be(false)
  end

  it "xs:all is order-free with foreign children rejected" do
    schema = Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="cfg">
          <xs:complexType>
            <xs:all>
              <xs:element name="a" type="xs:token"/>
              <xs:element name="b" type="xs:token"/>
            </xs:all>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
    expect(schema.valid?(Leptris::XML::Document.parse(
      %(<cfg><b>x</b><a>y</a></cfg>)))).to be(true)
    expect(schema.valid?(Leptris::XML::Document.parse(
      %(<cfg><a>x</a><c>z</c></cfg>)))).to be(false)
  end

  it "the well-formed mixed union validates correctly (#1615)" do
    schema = Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:simpleType name="intOrAuto">
          <xs:union memberTypes="xs:integer">
            <xs:simpleType>
              <xs:restriction base="xs:token">
                <xs:enumeration value="auto"/>
              </xs:restriction>
            </xs:simpleType>
          </xs:union>
        </xs:simpleType>
        <xs:element name="v" type="intOrAuto"/>
      </xs:schema>
    XSD
    expect(schema.simple_valid?("intOrAuto", "42")).to be(true)
    expect(schema.simple_valid?("intOrAuto", "auto")).to be(true)
    expect(schema.simple_valid?("intOrAuto", "zz")).to be(false)
    expect(schema.valid?(Leptris::XML::Document.parse(%(<v>42</v>)))).to be(true)
    expect(schema.valid?(Leptris::XML::Document.parse(%(<v>zz</v>)))).to be(false)
  end

  it "malformed schemas compile error-carrying and fail closed" do
    schema = Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:simpleType name="t">
          <xs:union memberTypes="xs:integer">
            <xs:simpleType><xs:restriction base="xs:token"><xs:enumeration value="auto"/></xs:simpleType>
          </xs:union>
        </xs:simpleType>
        <xs:element name="v" type="t"/>
      </xs:schema>
    XSD
    expect(schema.error).to include("not well-formed")
    expect(schema.valid?(Leptris::XML::Document.parse(%(<v>42</v>)))).to be(false)
  end
end

# libleptris 1.9.335 (#1626, from leptris-ruby#414): the OOXML
# wave — cross-namespace imports, prefixed type refs, and named
# content-model errors without ancestor cascade.
RSpec.describe "XSD cross-namespace imports (1.9.335, #1626)" do
  it "merges imported declarations under a compiling schema's own targetNamespace" do
    Dir.mktmpdir do |dir|
      iso = File.join(dir, "iso"); ms = File.join(dir, "ms")
      FileUtils.mkdir_p([iso, ms])
      File.write(File.join(iso, "inner.xsd"), <<~XSD)
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns:w="urn:w" targetNamespace="urn:w"
                   elementFormDefault="qualified">
          <xs:element name="doc">
            <xs:complexType><xs:sequence>
              <xs:element name="p" type="xs:token"
                          minOccurs="0" maxOccurs="unbounded"/>
            </xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
      XSD
      File.write(File.join(ms, "wrapper.xsd"), <<~XSD)
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns:w="urn:w" targetNamespace="urn:2010"
                   elementFormDefault="qualified">
          <xs:import namespace="urn:w"
                     schemaLocation="../iso/inner.xsd"/>
          <xs:element name="extra" type="xs:token"/>
        </xs:schema>
      XSD
      schema = Leptris::XML::XSD.compile_file(File.join(ms, "wrapper.xsd"))
      doc = Leptris::XML::Document.parse(%(<w:doc xmlns:w="urn:w"><w:p>x</w:p></w:doc>))
      expect(schema.valid?(doc)).to be(true)
    end
  end

  it "resolves prefixed QName type references" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "prefixed.xsd")
      File.write(path, <<~XSD)
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns:w="urn:w" targetNamespace="urn:w"
                   elementFormDefault="qualified">
          <xs:complexType name="CT_Border">
            <xs:attribute name="val" type="xs:token"/>
          </xs:complexType>
          <xs:element name="b" type="w:CT_Border"/>
        </xs:schema>
      XSD
      schema = Leptris::XML::XSD.compile_file(path)
      ok = Leptris::XML::Document.parse(%(<b xmlns="urn:w" val="x"/>))
      expect(schema.valid?(ok)).to be(true)
    end
  end

  it "names the offending child without ancestor cascade" do
    schema = Leptris::XML::XSD.compile(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns="urn:w" targetNamespace="urn:w"
                 elementFormDefault="qualified">
        <xs:complexType name="CT_Border">
          <xs:attribute name="val" type="xs:token"/>
        </xs:complexType>
        <xs:complexType name="CT_TblBorders">
          <xs:sequence>
            <xs:element name="top" type="CT_Border" minOccurs="0"/>
            <xs:element name="left" type="CT_Border" minOccurs="0"/>
            <xs:element name="bottom" type="CT_Border" minOccurs="0"/>
            <xs:element name="right" type="CT_Border" minOccurs="0"/>
            <xs:element name="insideH" type="CT_Border" minOccurs="0"/>
            <xs:element name="insideV" type="CT_Border" minOccurs="0"/>
          </xs:sequence>
        </xs:complexType>
        <xs:element name="tblBorders" type="CT_TblBorders"/>
      </xs:schema>
    XSD
    bad = Leptris::XML::Document.parse(
      %(<tblBorders xmlns="urn:w"><top val="a"/><left val="b"/>) +
      %(<bottom val="c"/><insideH val="d"/><right val="e"/>) +
      %(<insideV val="f"/></tblBorders>))
    errors = schema.validate_errors(bad)
    # one report, naming the misordered child — no ancestor cascade
    expect(errors.size).to eq(1)
    expect(errors.first).to include("at 'right'")
  end
end
