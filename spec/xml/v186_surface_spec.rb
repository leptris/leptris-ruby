# frozen_string_literal: true

# Libleptris 1.9.182-186 (the lockstep): RNG #1137 regression
# fix — documents omitting an <optional> element failed validation
# since 1.9.179 (the #1121 diagnostics engaged the matcher's
# short-circuit during backtracking probes). Pinned here because
# 1.9.181.0 shipped the regression.
RSpec.describe "libleptris 1.9.186 surfaces (lockstep)" do
  schema = <<~RNG
    <element name="r" xmlns="http://relaxng.org/ns/structure/1.0">
      <element name="a"><text/></element>
      <optional>
        <element name="b"><text/></element>
      </optional>
    </element>
  RNG

  it "an omitted <optional> element stays valid (upstream #1137)" do
    rng = Leptris::XML::RelaxNG.parse(schema)
    doc = Leptris::XML::Document.parse("<r><a>1</a></r>")
    expect(rng.validate(doc)).to be_empty
  end

  it "the present <optional> form stays valid too" do
    rng = Leptris::XML::RelaxNG.parse(schema)
    doc = Leptris::XML::Document.parse("<r><a>1</a><b>2</b></r>")
    expect(rng.validate(doc)).to be_empty
  end

  it "real mismatches still accumulate after the fix" do
    rng = Leptris::XML::RelaxNG.parse(schema)
    doc = Leptris::XML::Document.parse("<r><a>1</a><c/><d/></r>")
    errors = rng.validate(doc)
    expect(errors.size).to be > 1
    expect(errors.join("\n")).to include("c")
  end
end
