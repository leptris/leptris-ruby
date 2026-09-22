# frozen_string_literal: true

require "spec_helper"

# Typed plan scalars (moxml consumer face, #1269a): [slot, tag]
# attr/text entries cast C-side — no Ruby String for numeric/
# boolean slots; strtod keeps double precision (the engine's
# float getter is 32-bit); unparseable input degrades to the raw
# String. The plan_structs_typed? marker gates consumer probing.
RSpec.describe "Native.plan_structs typed entries" do
  let(:doc) { Leptris::XML::Document.parse(xml) }
  let(:xml) do
    %(<r><item price="19.99" qty="3" ok="yes">42</item>) +
      %(<item price="bad" qty="x" ok="0">7</item></r>)
  end

  it "declares the capability marker" do
    expect(Leptris::XML::Native.plan_structs_typed?).to be(true)
  end

  it "casts typed slots and degrades unparseable input" do
    item = Struct.new(:price, :qty, :ok, :label)
    spec = { "item" => [item,
                        { "price" => [:price, 2], "qty" => [:qty, 1],
                          "ok" => [:ok, 3] },
                        [:label, 1], nil] }.freeze
    roots = Leptris::XML::Native.plan_structs(doc, doc.root.c_address, spec)

    expect(roots[0].price).to eq(19.99)
    expect(roots[0].qty).to eq(3)
    expect(roots[0].ok).to be(true)
    expect(roots[0].label).to eq(42)

    expect(roots[1].price).to eq("bad")
    expect(roots[1].qty).to eq("x")
    expect(roots[1].ok).to be(false)
    expect(roots[1].label).to eq(7)
  end
end
