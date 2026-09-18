# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# lutaml/moxml#249 plan layer: snapshot_rows is the lean element row
# stream — one 4-tuple per element, names interned, no text rows.
RSpec.describe "snapshot_rows", if: defined?(Leptris::XML::NativeNode) &&
  Leptris::XML::Native.respond_to?(:snapshot_rows) do
  let(:doc) do
    Leptris::XML::Document.parse(
      %(<r a="1" b="2"><c>t1</c><d><e/></d></r>))
  end

  it "yields one 4-tuple per element, pre-order" do
    rows = Leptris::XML::Native.snapshot_rows(doc, doc.root.c_address)

    expect(rows.map { |r| [r[0], r[3]] })
      .to eq([["r", 0], ["c", 1], ["d", 1], ["e", 2]])
  end

  it "carries flat attribute pairs and first text" do
    rows = Leptris::XML::Native.snapshot_rows(doc, doc.root.c_address)

    expect(rows[0][1]).to eq(%w[a 1 b 2])
    expect(rows[1][1]).to eq([])
    expect(rows[1][2]).to eq("t1")
    expect(rows[3][2]).to be_nil
  end

  it "interns element and attribute names" do
    doc2 = Leptris::XML::Document.parse(%(<r a="9"/>))
    rows = Leptris::XML::Native.snapshot_rows(doc2, doc2.root.c_address)

    name, (an, _av) = rows[0]
    expect(name).to be_frozen
    expect(name).to equal(rows[0][0])
    expect(an).to be_frozen
    expect(an).to equal(doc.root.c_address ? rows[0][1][0] : an)
  end
end
