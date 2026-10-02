# frozen_string_literal: true

require "spec_helper"

# NativeNode#content must answer the COMMENT payload
# (leptris_comment_node_get_content) — comment-kind NNs returned
# nil while text/CDATA worked (#344). The binding Comment face was
# always correct; this is the C-side walk-minted accessor.
RSpec.describe "NativeNode#content across node kinds (#344)" do
  it "returns the comment payload for comment-kind nodes" do
    doc = Leptris::XML::Document.parse(%(<doc><!-- c --><t>tx</t></doc>))
    root = doc.native_node
    comment = root.children.find { |c| c.node_type == :comment }
    expect(comment.content).to eq(" c ")
  end

  it "returns the CDATA payload for cdata-kind nodes" do
    doc = Leptris::XML::Document.parse(%(<doc><x><![CDATA[cd]]></x></doc>))
    x = doc.native_node.children.first
    nn = x.children.find { |c| c.node_type == :cdata }
    expect(nn.content).to eq("cd")
  end

  it "aggregates element text as before" do
    doc = Leptris::XML::Document.parse(%(<doc><t>tx</t></doc>))
    nn = doc.native_node.children.first
    expect(nn.content).to eq("tx")
  end
end
