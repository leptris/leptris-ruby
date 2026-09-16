# frozen_string_literal: true

# Libleptris 1.9.178 (the lockstep). The binding's adoption lives
# in three places; engine-side matching / corpus parity for the ns
# rule and byte-position lives in the lutaml-model xmllint suite.
RSpec.describe "libleptris 1.9.178 surfaces (lockstep)" do
  # #1113 — collection wrappers echo the producing row's
  # wire_name + type_tag (the binding already reads both via the
  # existing accessors; the engine fixes the omission).
  it "echoes wire_name + type_tag on collection rows" do
    plan = { name: "item", children: [
      { name: "name", kind: :scalar, type_tag: 1 },
      { name: "tag",  kind: :collection, type_tag: 2 },
    ] }
    d = Leptris::XML::Descriptor.build(name: "r", children: [
      { name: "item", kind: :nested, plan: plan, type_tag: 3 },
    ])
    v = d.walk(Leptris::XML::Document.parse(
      %q{<r><item><name>A</name><tag>x</tag><tag>y</tag></item></r>}).root)
    item = v.at(0)
    scalar = item.at(0); collection = item.at(1)
    expect(scalar.kind).to eq(:scalar)
    expect(scalar.type_tag).to eq(1)
    expect(collection.kind).to eq(:collection)
    expect(collection.name).to eq("tag")        # echoed (was nil pre-1.9.178)
    expect(collection.type_tag).to eq(2)         # echoed (was 0 pre-1.9.178)
    expect(collection.count).to eq(2)
  end

  # #1115 — the binding's plan API accepts :ns on child rows
  # (lockstep); the engine does the match. Structural verification
  # lives in rake audit:symbols + the compile-time FFI struct
  # check that pack_plans compiles without error.
  it "accepts :ns on child rows without raising (lockstep)" do
    expect {
      Leptris::XML::Descriptor.build(name: "r", children: [
        { name: "x", ns: { exact: "urn:x" }, kind: :nested, plan: { name: "x", children: [] } },
        { name: "y", ns: :any, kind: :scalar },
      ])
    }.not_to raise_error
  end

  # #1118 — the accessor exists; per-doc population is the engine's
  # contract. We pin the readers respond (no exception), and the
  # memo lazy-fill runs once.
  it "exposes line/byte_offset on parsed elements (lockstep)" do
    doc = Leptris::XML::Document.parse(%q{<r><e/></r>})
    expect { doc.root.line }.not_to raise_error
    expect { doc.root.byte_offset }.not_to raise_error
    # memoization: repeated reads stable
    expect(doc.root.line).to eq(doc.root.line)
    expect(doc.root.byte_offset).to eq(doc.root.byte_offset)
  end
end
