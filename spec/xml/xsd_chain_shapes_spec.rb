# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# leptris-ruby#440 shapes A/B (libleptris 1.9.350): chain-compiled
# schemas — extension bases defined AFTER their derived types fold
# after the whole schema merges, subfiles resolve their own relative
# schemaLocations against their own directory, and attribute type
# names resolve (ns, name)-first so same-name simpleTypes across
# imported namespaces keep distinct value spaces.
RSpec.describe "XSD chain-compile shapes (#440)" do
  around do |ex|
    Dir.mktmpdir do |dir|
      @dir = dir
      ex.run
    end
  end

  def write(rel, content)
    path = File.join(@dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  it "folds forward-referenced extension bases through subfile dirs" do
    write("root.xsd", <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns="urn:a" targetNamespace="urn:a">
        <xs:import namespace="urn:wrap" schemaLocation="sub/wrap.xsd"/>
        <xs:complexType name="CT_App">
          <xs:sequence>
            <xs:element name="outer" type="CT_Outer"/>
          </xs:sequence>
        </xs:complexType>
        <xs:element name="app" type="CT_App"/>
      </xs:schema>
    XSD
    # chameleon wrapper: the subfile's OWN imports resolve against
    # ITS directory (../lib/base.xsd), and base.xsd's same-dir
    # more.xsd against ITS directory — not the compiled file's.
    write("sub/wrap.xsd", <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:import namespace="urn:a" schemaLocation="../lib/base.xsd"/>
      </xs:schema>
    XSD
    write("lib/base.xsd", <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns="urn:a" targetNamespace="urn:a">
        <xs:import namespace="urn:a" schemaLocation="more.xsd"/>
        <xs:complexType name="CT_Outer">
          <xs:complexContent>
            <xs:extension base="CT_Inner">
              <xs:sequence>
                <xs:element name="ownOuter"/>
              </xs:sequence>
            </xs:extension>
          </xs:complexContent>
        </xs:complexType>
        <xs:complexType name="CT_Inner">
          <xs:complexContent>
            <xs:extension base="CT_Base">
              <xs:sequence>
                <xs:element name="fromInner"/>
              </xs:sequence>
            </xs:extension>
          </xs:complexContent>
        </xs:complexType>
      </xs:schema>
    XSD
    write("lib/more.xsd", <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns="urn:a" targetNamespace="urn:a">
        <xs:complexType name="CT_Base">
          <xs:sequence>
            <xs:element name="fromBase"/>
          </xs:sequence>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Leptris::XML::XSD.compile_file(File.join(@dir, "root.xsd"))
    doc = Leptris::XML.parse(
      '<a:app xmlns:a="urn:a"><outer>' \
      "<fromBase/><fromInner/><ownOuter/></outer></a:app>"
    )
    # base content first, derived content after, at every hop
    expect(schema.validate_errors(doc)).to eq([])
    bad = Leptris::XML.parse(
      '<a:app xmlns:a="urn:a"><outer>' \
      "<fromBase/><bogus/></outer></a:app>"
    )
    expect(schema.validate_errors(bad)).not_to be_empty
  end

  it "resolves attribute types in the declaring namespace" do
    write("w.xsd", <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns="urn:w" targetNamespace="urn:w">
        <xs:import namespace="urn:m" schemaLocation="m.xsd"/>
        <xs:simpleType name="ST_Jc">
          <xs:restriction base="xs:string">
            <xs:enumeration value="a"/>
            <xs:enumeration value="b"/>
          </xs:restriction>
        </xs:simpleType>
        <xs:complexType name="CT_WJc">
          <xs:attribute name="val" type="ST_Jc"/>
        </xs:complexType>
        <xs:element name="wDef" type="CT_WJc"/>
      </xs:schema>
    XSD
    write("m.xsd", <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns="urn:m" targetNamespace="urn:m">
        <xs:simpleType name="ST_Jc">
          <xs:restriction base="xs:string">
            <xs:enumeration value="a"/>
            <xs:enumeration value="b"/>
            <xs:enumeration value="centerGroup"/>
          </xs:restriction>
        </xs:simpleType>
        <xs:complexType name="CT_MJc">
          <xs:attribute name="val" type="ST_Jc"/>
        </xs:complexType>
        <xs:element name="mDef" type="CT_MJc"/>
      </xs:schema>
    XSD

    schema = Leptris::XML::XSD.compile_file(File.join(@dir, "w.xsd"))
    # m's ST_Jc lists centerGroup — the (urn:m, ST_Jc) entry serves
    # m's attribute row, not w's same-name type
    m = Leptris::XML.parse(
      '<m:mDef xmlns:m="urn:m" m:val="centerGroup"/>'
    )
    expect(schema.validate_errors(m)).to eq([])
    # ns-keying is not a free-for-all: w's ST_Jc lacks centerGroup
    wbad = Leptris::XML.parse(
      '<w:wDef xmlns:w="urn:w" w:val="centerGroup"/>'
    )
    expect(schema.validate_errors(wbad)).not_to be_empty
    wok = Leptris::XML.parse('<w:wDef xmlns:w="urn:w" w:val="a"/>')
    expect(schema.validate_errors(wok)).to eq([])
  end
end
