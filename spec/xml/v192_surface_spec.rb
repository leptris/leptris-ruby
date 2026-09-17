# frozen_string_literal: true

require "tmpdir"

# Libleptris 1.9.189-192 (the lockstep): the metanorma chain closes
# — combine-merge UAF, XSD \i/\c pattern classes, whole-value
# anchors; the whole-report face leptris_rng_error_report (1.9.190,
# kind/offender taxonomy); attributes behind <ref> consumed in both
# the verdict (1.9.191) and the diagnostic walk (1.9.192); and
# externalRef in bare-<element> schemas.
RSpec.describe "libleptris 1.9.192 surfaces (lockstep)" do
  RNG_NS = "http://relaxng.org/ns/structure/1.0"

  KINDS = %w[
    not-allowed-anywhere not-allowed-here not-allowed-yet incomplete
    missing-required-attr attr-not-allowed attr-value-invalid
    char-content-invalid
  ].freeze

  it "validate_report returns the whole structured list (1.9.190)" do
    schema = <<~RNG
      <element name="r" xmlns="#{RNG_NS}">
        <attribute name="req"><text/></attribute>
        <element name="c"><text/></element>
      </element>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)

    expect(rng.validate_report(
      Leptris::XML::Document.parse(%q{<r req="x"><c>t</c></r>}))).to eq([])

    report = rng.validate_report(
      Leptris::XML::Document.parse(%q{<r extra="1"><c>t</c></r>}))
    kinds = report.map { |r| r[:kind] }
    expect(kids = kinds - KINDS).to eq([])
    expect(kinds).to include("missing-required-attr")
    expect(kinds).to include("attr-not-allowed")
    report.each do |r|
      expect(r[:line]).to be_an(Integer)
      expect(r[:column]).to be_an(Integer)
      expect(r[:message]).to be_a(String)
      expect(r[:offender]).to be_a(String).or be_nil
    end
  end

  it "consumes attribute lists behind a <ref>, verdict and diagnostics (1.9.191/1.9.192)" do
    schema = <<~RNG
      <grammar xmlns="#{RNG_NS}">
        <start>
          <element name="r">
            <ref name="Root-Attributes"/>
            <element name="c"><text/></element>
          </element>
        </start>
        <define name="Root-Attributes">
          <attribute name="id"><text/></attribute>
        </define>
      </grammar>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)
    doc = Leptris::XML::Document.parse(%q{<r id="x"><c>t</c></r>})
    expect(rng.valid?(doc)).to be true
    # the diagnostic walk must not report the consumed attributes
    expect(rng.validate(doc)).to eq([])
    expect(rng.validate_report(doc)).to eq([])
  end

  it "supports XSD \\i and \\c pattern classes (1.9.189)" do
    schema = <<~RNG
      <element name="r" xmlns="#{RNG_NS}">
        <data type="string"><param name="pattern">\\i\\c*</param></data>
      </element>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)
    expect(rng.valid?(Leptris::XML::Document.parse("<r>abc</r>"))).to be true
    expect(rng.valid?(Leptris::XML::Document.parse("<r>1a</r>"))).to be false
  end

  it "resolves externalRef inside a bare-<element> schema (1.9.190)" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "child.rng"), <<~RNG)
        <grammar xmlns="#{RNG_NS}">
          <start><element name="e"><text/></element></start>
        </grammar>
      RNG
      host = File.join(dir, "host.rng")
      File.write(host, <<~RNG)
        <element name="r" xmlns="#{RNG_NS}">
          <externalRef href="child.rng"/>
        </element>
      RNG
      rng = Leptris::XML::RelaxNG::Schema.parse_file(host)
      expect(rng.valid?(Leptris::XML::Document.parse("<r><e>t</e></r>")))
        .to be true
    end
  end

  it "survives include merges with inherited combine (1.9.189 UAF)" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "lib.rng"), <<~RNG)
        <grammar xmlns="#{RNG_NS}">
          <define name="part">
            <element name="p"><text/></element>
          </define>
        </grammar>
      RNG
      host = File.join(dir, "host.rng")
      File.write(host, <<~RNG)
        <grammar xmlns="#{RNG_NS}">
          <include href="lib.rng"/>
          <start>
            <element name="r">
              <zeroOrMore><ref name="part"/></zeroOrMore>
            </element>
          </start>
        </grammar>
      RNG
      rng = Leptris::XML::RelaxNG::Schema.parse_file(host)
      expect(rng.valid?(Leptris::XML::Document.parse("<r><p>x</p></r>")))
        .to be true
    end
  end
end
