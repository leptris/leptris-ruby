# frozen_string_literal: true

require "spec_helper"

# Element#append_children / children= batching (#366): one C
# crossing for N children, source order preserved, lift-needing
# children still take the full path.
RSpec.describe "Element#append_children (#366)" do
  it "appends a batch in source order" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    kids = (1..50).map { |i| doc.create_element("e#{i}") }
    doc.root.append_children(kids)
    expect(doc.root.element_children.map(&:name)).to eq(kids.map(&:name))
  end

  it "children= replaces wholesale through the batch path" do
    doc = Leptris::XML::Document.parse(%(<r><old/></r>))
    kids = (1..30).map { |i| doc.create_element("n#{i}") }
    doc.root.children = kids
    expect(doc.root.element_children.map(&:name)).to eq(kids.map(&:name))
    expect(doc.root.to_xml).to include("<n1/>")
  end

  it "preserves order when a namespaced child needs the lift path" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    src = Leptris::XML::Document.parse(
      %(<a:o xmlns:a="urn:a"><a:i/></a:o>))
    named = src.root.element_children.first
    plain = doc.create_element("before")
    after = doc.create_element("after")
    doc.root.append_children([plain, named, after])
    expect(doc.root.element_children.map(&:name)).to eq(%w[before i after])
    expect(doc.root.element_children[1].namespace&.href).to eq("urn:a")
  end

  it "adopts cross-document children with memo invalidation" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    other = Leptris::XML::Document.parse(%(<o><c1/><c2/></o>))
    kids = other.root.element_children.to_a
    doc.root.append_children(kids)
    expect(doc.root.element_children.map(&:name)).to eq(%w[c1 c2])
    expect(other.root.element_children).to be_empty
  end

  it "mixed content with strings falls back per-child" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    doc.root.append_children([doc.create_element("a"), "<b/>"])
    expect(doc.root.children.map(&:name)).to eq(%w[a b])
  end
end
