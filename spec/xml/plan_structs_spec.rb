# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# Native struct-plan executor: the consumer's shape compiles to
# {name => [Struct class, attrs, text slot, children slot]}; C mints
# the typed objects directly — zero Ruby frames per element.
RSpec.describe "plan_structs", if: defined?(Leptris::XML::NativeNode) &&
  Leptris::XML::Native.respond_to?(:plan_structs) do
  let(:xml) do
    %(<catalog><record id="r0" kind="k0"><field name="f0" unit="u0">v 0.0</field><field name="f1" unit="u1">v 0.1</field></record><record id="r1" kind="k1"><field name="f0" unit="u0">v 1.0</field></record></catalog>)
  end

  let(:doc) { Leptris::XML::Document.parse(xml) }

  it "mints typed structs with attrs, text, and children" do
    field = Struct.new(:name, :unit, :value)
    record = Struct.new(:id, :kind, :fields)
    spec = {
      "record" => [record, { "id" => :id, "kind" => :kind }, nil, :fields],
      "field" => [field, { "name" => :name, "unit" => :unit }, :value, nil],
    }

    rows = Leptris::XML::Native.plan_structs(
      doc, doc.root.c_address, spec)

    expect(rows.size).to eq(2)
    expect(rows[0].id).to eq("r0")
    expect(rows[0].fields.size).to eq(2)
    expect(rows[0].fields[0]).to eq(field.new("f0", "u0", "v 0.0"))
    expect(rows[1].fields[0].value).to eq("v 1.0")
  end

  it "treats unmatched elements as barriers (moxml::Plan parity)" do
    doc = Leptris::XML::Document.parse(
      %(<catalog><wrap><record id="r9"/></wrap><record id="r8"/></catalog>))
    record = Struct.new(:id, :fields)
    spec = { "record" => [record, { "id" => :id }, nil, :fields] }

    rows = Leptris::XML::Native.plan_structs(doc, doc.root.c_address, spec)

    # records under the unmatched wrap surface at top level, like
    # Moxml::Plan
    expect(rows.map { |r| r.id }).to eq(%w[r9 r8])
  end
end
