# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# The face ships in the native ext; ruby-platform installs without a
# built bundle take a skip (every native spec's convention).

# TODO.sota/04 (moxml build row): NativeNode#add_element_full is the
# ONE-crossing construction face — create + attrs + attach + optional
# text + version bump + consumer mint, all in C off the parent
# wrapper's struct. Nokogiri's equivalent build shape is five separate
# crossings; this face is one.
RSpec.describe "NativeNode#add_element_full",
               if: defined?(Leptris::XML::NativeNode) &&
                   Leptris::XML::NativeNode.method_defined?(:add_element_full) do
  let(:doc) { Leptris::XML::Document.parse("<r><a/></r>") }
  let(:root) { doc.native_node }

  def build(parent, name, attrs, text = nil)
    parent.add_element_full(name, attrs, text)
  end

  it "creates, names, attaches, and sets text in one crossing" do
    row = build(root, "field", %w[name f0 unit u0], "value 0")
    expect(row).not_to be_nil
    expect(row.name).to eq("field")
    expect(root.children_read.to_a.map { |c| c.name.to_s }).to include("field")
    expect(row.content).to eq("value 0")
  end

  it "mints the registered consumer klass and caches identity" do
    row1 = build(root, "x", [], nil)
    row2 = build(root, "y", [], nil)
    expect(row1.class).to equal(row2.class)
    again = root.children_read.to_a.find { |c| c.name.to_s == "x" }
    expect(again).to equal(row1)
  end

  it "advances the document version (memos retire)" do
    v0 = doc.version
    build(root, "x", [], nil)
    expect(doc.version).to eq(v0 + 1)
  end

  it "keeps attribute values intact" do
    row = build(root, "f", %w[name f9 unit u9], nil)
    expect(row.attribute_nodes.map { |a| [a.name, a.value] })
      .to contain_exactly(%w[name f9], %w[unit u9])
  end
end
