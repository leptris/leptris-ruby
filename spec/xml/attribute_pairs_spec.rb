# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#278: read-only attribute listing as [name, value]
# pairs — no Attr objects, document order, duplicates included.
# The native face (>= this release) answers in one crossing; the
# fallback derives from each_attribute with identical results.
RSpec.describe Leptris::XML::Element do
  let(:xml) do
    '<catalog><record id="r0" kind="k0"><field name="f0" unit="u0">v</field></record></catalog>'
  end
  let(:doc) { Leptris::XML::Document.parse(xml) }
  let(:record) { doc.root.children.find { |c| c.is_a?(described_class) } }

  it "equals the node path" do
    node_derived = record.each_attribute.to_a.map { |a| [a.name, a.value] }
    expect(record.attribute_pairs).to eq(node_derived)
  end

  it "preserves document order" do
    expect(record.attribute_pairs.map(&:first)).to eq(%w[id kind])
  end

  it "answers in document order for every element" do
    field = record.children.find { |c| c.is_a?(described_class) }
    expect(field.attribute_pairs).to eq([%w[name f0], %w[unit u0]])
  end

  it "invalidates on mutation" do
    expect(record.attribute_pairs).to eq([%w[id r0], %w[kind k0]])
    record["kind"] = "k9"
    expect(record.attribute_pairs).to eq([%w[id r0], %w[kind k9]])
  end
end

RSpec.describe "Leptris::XML::Element attribute_nodes via the rows face" do
  let(:xml) { %(<r><e a="v" xmlns:p="urn:p" p:b="w"/></r>) }
  let(:doc) { Leptris::XML::Document.parse(xml) }

  it "equals the chain path and carries usable handles" do
    fast = doc.root.children.first.attribute_nodes.map { |a| [a.name, a.value] }
    slow = doc.root.children.first.each_attribute.to_a.map { |a| [a.name, a.value] }
    expect(fast).to eq(slow)

    namespaced = doc.root.children.first.attribute_nodes
      .find { |a| a.name == "p:b" }
    expect(namespaced.namespace_uri).to eq("urn:p")
  end
end
