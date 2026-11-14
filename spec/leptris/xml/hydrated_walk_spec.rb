# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#631 — shape (b): the subtree prime hydrates each
# element's attribute packet and each leaf's content on the SAME
# crossing, and the attribute_pairs face serves the hydration
# cache-first (write-back memoizes cold captures too). The memo
# identity is the falsifiable proof: repeat reads answer the SAME
# Ruby object only when a memo serves them — on main they were
# fresh arrays every call.
RSpec.describe "leptris hydrated walk (shape b)" do
  let(:xml) do
    '<root a="1" b="2"><child x="y">text here</child>' \
      '<other/><!-- note --></root>'
  end

  def registered_doc
    doc = Leptris::XML.parse(xml)
    doc.register_wrapper_klasses(
      [Leptris::XML::NativeNode, nil, nil, nil, nil]
    )
    doc.native_node.children # the prime crossing
    doc
  end

  it "serves attribute_pairs from the hydration (same object on repeat reads)" do
    doc = registered_doc
    addr = doc.native_node.children.first.address
    a1 = Leptris::XML::Native.attribute_pairs(doc, addr)
    a2 = Leptris::XML::Native.attribute_pairs(doc, addr)
    expect(a1).to eq(["x", "y"])
    expect(a1).to equal(a2)
  end

  it "hydrates the root's own packet shape at depth one" do
    doc = registered_doc
    addr = doc.native_node.address
    expect(Leptris::XML::Native.attribute_pairs(doc, addr))
      .to eq(["a", "1", "b", "2"])
  end

  it "retires the hydration on mutation (fresh capture, correct values)" do
    doc = registered_doc
    elem = doc.native_node.children.first
    elem.set_attribute("x", "z")
    fresh = Leptris::XML::Native.attribute_pairs(doc, elem.address)
    expect(fresh).to eq(["x", "z"])
    again = Leptris::XML::Native.attribute_pairs(doc, elem.address)
    expect(fresh).to equal(again) # the write-back memoizes the capture
  end

  it "keeps cold (non-registered) documents correct" do
    doc = Leptris::XML.parse(xml)
    addr = doc.native_node.children.first.address
    expect(Leptris::XML::Native.attribute_pairs(doc, addr)).to eq(["x", "y"])
  end

  it "hydrates leaf content so the first content read answers from the walk" do
    doc = registered_doc
    text = doc.native_node.children.first.children.first
    expect(text.content).to eq("text here")
  end
end
