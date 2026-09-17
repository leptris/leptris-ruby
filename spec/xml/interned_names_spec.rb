# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# lutaml/moxml#249: element names read through the native layer are
# interned fstrings — shared and frozen per distinct name.
RSpec.describe "interned native names", if: defined?(Leptris::XML::NativeNode) do
  it "returns the same object for identical names across documents" do
    doc1 = Leptris::XML::Document.parse(%q{<r><item/></r>})
    doc2 = Leptris::XML::Document.parse(%q{<r><item/></r>})
    a = doc1.native_node.children.first.name
    b = doc2.native_node.children.first.name
    expect(a).to equal(b)
    expect(a).to eq("item")
  end

  it "returns frozen strings" do
    doc = Leptris::XML::Document.parse(%q{<r><item/></r>})
    name = doc.native_node.children.first.name
    expect(name).to be_frozen
    expect { name << "x" }.to raise_error(FrozenError)
  end

  it "still reads updates after a rename" do
    doc = Leptris::XML::Document.parse(%q{<r><item/></r>})
    node = doc.native_node.children.first
    doc.root.element_children.first.name = "renamed"
    expect(node.name).to eq("renamed")
    expect(node.name).to be_frozen
  end

  it "keeps UTF-8 names intact" do
    doc = Leptris::XML::Document.parse(%q{<r><élément/></r>})
    name = doc.native_node.children.first.name
    expect(name).to eq("élément")
    expect(name.encoding).to eq(Encoding::UTF_8)
  end
end
