# frozen_string_literal: true

# Libleptris 1.9.179-181 (the lockstep): RNG error accumulation
# (#878) + parser-recorded source positions (#1124) + the parse-
# failure ASAN/leak fixes (1.9.180).
RSpec.describe "libleptris 1.9.181 surfaces (lockstep)" do
  it "accumulates every RNG validation error, not just the first" do
    schema = <<~RNG
      <element name="r" xmlns="http://relaxng.org/ns/structure/1.0">
        <element name="a"><text/></element>
        <element name="b"><text/></element>
      </element>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)
    doc = Leptris::XML::Document.parse(%q{<r><a>1</a><c/><d/></r>})
    errors = rng.validate(doc)
    expect(errors.size).to be > 1   # c and d both reported (was: first only)
    expect(errors.join("\n")).to include("c")
    expect(errors.join("\n")).to include("d")
  end

  it "exposes parser-recorded source_position (Jing columns)" do
    doc = Leptris::XML::Document.parse("<r>\n  <item x='1'>t</item>\n</r>")
    pos = doc.root.element_children.first.source_position
    expect(pos[:line]).to eq(2)
    expect(pos[:col_start]).to be > 0
    expect(pos[:col_end]).to be >= pos[:col_start]
    # stable across reads (immutable)
    expect(doc.root.element_children.first.source_position).to eq(pos)
  end

  it "source_position is zeros for programmatically-created nodes" do
    doc = Leptris::XML::Document.create
    e = doc.create_element("new")
    expect(e.source_position).to eq(line: 0, col_start: 0, col_end: 0)
  end
end
