# frozen_string_literal: true

# Libleptris 1.9.194 (the lockstep): define bodies are sibling
# lists — a <ref> to a multi-member define matches the WHOLE body
# (an implicit group), and inside a CHOICE the zero-width
# <text/>/empty branch no longer starves child-consuming
# alternatives (metanorma DocumentBody / inline TextElement
# shapes). Diagnostics gain Jing PatternMatcher semantics.
RSpec.describe "libleptris 1.9.194 surfaces (lockstep)" do
  RNG_NS = "http://relaxng.org/ns/structure/1.0"

  it "a ref to a multi-member define body matches the whole body" do
    schema = <<~RNG
      <grammar xmlns="#{RNG_NS}">
        <start>
          <element name="doc"><ref name="DocumentBody"/></element>
        </start>
        <define name="DocumentBody">
          <optional><element name="preface"><text/></element></optional>
          <element name="sections"><text/></element>
        </define>
      </grammar>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)
    # both members (preface optional)
    expect(rng.valid?(Leptris::XML::Document.parse(
      "<doc><preface>p</preface><sections>s</sections></doc>"))).to be true
    # the body TAIL is required — matching only the head must fail
    expect(rng.valid?(Leptris::XML::Document.parse(
      "<doc><preface>p</preface></doc>"))).to be false
    # tail alone also valid (preface optional)
    expect(rng.valid?(Leptris::XML::Document.parse(
      "<doc><sections>s</sections></doc>"))).to be true
  end

  it "a zero-width choice branch does not starve child consumers" do
    schema = <<~RNG
      <grammar xmlns="#{RNG_NS}">
        <start>
          <element name="p">
            <zeroOrMore>
              <choice>
                <element name="b"><text/></element>
                <text/>
              </choice>
            </zeroOrMore>
          </element>
        </start>
      </grammar>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)
    expect(rng.valid?(Leptris::XML::Document.parse(
      "<p>plain <b>bold</b> tail</p>"))).to be true
    expect(rng.valid?(Leptris::XML::Document.parse(
      "<p><b>x</b></p>"))).to be true
    expect(rng.valid?(Leptris::XML::Document.parse(
      "<p><i>no</i></p>"))).to be false
  end

  it "diagnostics keep the Jing attribution through ref splicing" do
    schema = <<~RNG
      <grammar xmlns="#{RNG_NS}">
        <start>
          <element name="doc"><ref name="DocumentBody"/></element>
        </start>
        <define name="DocumentBody">
          <optional><element name="preface"><text/></element></optional>
          <element name="sections"><text/></element>
        </define>
      </grammar>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)
    report = rng.validate_report(
      Leptris::XML::Document.parse("<doc><preface>p</preface></doc>"))
    expect(report).not_to be_empty
    expect(report.first[:line]).to be_an(Integer)
    expect(report.first[:message]).to be_a(String)
  end
end
