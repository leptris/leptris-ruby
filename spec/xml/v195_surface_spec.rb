# frozen_string_literal: true

# Libleptris 1.9.195 (the lockstep): required attributes behind
# <ref> are enforced (#1164), and stray character data under
# element-only content is rejected (#1153 — the anyName wildcard
# laxness found while pinning v188 and filed upstream).

RSpec.describe "libleptris 1.9.195 surfaces (lockstep)" do
  RNG_NS = "http://relaxng.org/ns/structure/1.0"

  it "rejects stray character data under element-only content (#1153)" do
    schema = <<~RNG
      <element name="r" xmlns="#{RNG_NS}">
        <zeroOrMore><element><anyName/></element></zeroOrMore>
      </element>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)
    expect(rng.valid?(Leptris::XML::Document.parse("<r>text</r>"))).to be false
    expect(rng.valid?(Leptris::XML::Document.parse("<r><a/></r>"))).to be true
    # NOTE: the verdict rejects, but no error is recorded yet (report
    # and legacy channels both empty for this case) — filed upstream
    # on leptris/leptris#1153; not pinned until fixed.
  end

  it "enforces required attributes behind a <ref> (#1164)" do
    schema = <<~RNG
      <grammar xmlns="#{RNG_NS}">
        <start>
          <element name="r"><ref name="Root-Attributes"/></element>
        </start>
        <define name="Root-Attributes">
          <attribute name="id"><text/></attribute>
        </define>
      </grammar>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)
    expect(rng.valid?(Leptris::XML::Document.parse(%q{<r id="x"/>}))).to be true
    expect(rng.valid?(Leptris::XML::Document.parse("<r/>"))).to be false
    kinds = rng.validate_report(
      Leptris::XML::Document.parse("<r/>")).map { |r| r[:kind] }
    expect(kinds).to include("missing-required-attr")
  end
end
