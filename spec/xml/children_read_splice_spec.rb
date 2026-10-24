# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#545: the #507 contract face on the BINDING surface.
# moxml's children fast path and its splice-safety probe call
# children_read on the binding Element; with the face only on
# NativeNode the probe died on NoMethodError (rescued to "unsafe")
# and the fast path never engaged on any release. The law: prime →
# splice → read answers the post-splice tree.
RSpec.describe "Leptris::XML::Node#children_read (the #507 face on the binding surface)" do
  let(:doc) { Leptris::XML::Document.parse("<r><a/>\n<b/></r>") }
  let(:root) { doc.root }

  it "is exposed on the binding classes" do
    expect(root).to respond_to(:children_read)
  end

  it "answers the same children as children" do
    expect(root.children_read.to_a.map(&:name)).to eq(root.children.to_a.map(&:name))
  end

  it "reflects a sibling splice after the memo was primed (#545)" do
    root.children_read.to_a # prime the memo
    a = root.children.to_a.first
    a.add_next_sibling(doc.create_element("x"))
    names = root.children_read.to_a
                            .select(&:element?)
                            .map { |n| n.name.to_s }
    expect(names).to eq(%w[a x b])
  end

  it "reflects a child splice through the native insert face" do
    root.children_read.to_a
    child = root.children.to_a.first
    Leptris::XML::Native.insert_binding_child(doc, child.c_address,
                                              doc.create_element("y").c_address, 2)
    names = root.children_read.to_a.select(&:element?).map { |n| n.name.to_s }
    expect(names).to eq(%w[a y b])
  end
end
