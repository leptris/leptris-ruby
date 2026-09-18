# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# leptris-ruby#244: rename + namespace-clear through a
# NativeNode-bridged reference must serialize identically to the
# literal-call sequence on the same object. Verified fixed across
# 1.9.181+; this pins it.
RSpec.describe "namespace-clear parity through native bridges",
               if: defined?(Leptris::XML::NativeNode) do
  let(:xml) { %(<root xmlns:jats="http://jats"><jats:p>text</jats:p></root>) }

  def bridged_child(doc)
    ::Leptris::XML::Node.wrap(
      ::FFI::Pointer.new(doc.native_node.children.first.address), doc)
  end

  it "default_namespace clear matches literal vs bridged" do
    literal = Leptris::XML::Document.parse(xml).root.children.first
    literal.name = "p"
    literal.default_namespace = ""

    doc = Leptris::XML::Document.parse(xml)
    bridged = bridged_child(doc)
    expect(bridged).to equal(doc.root.children.first)
    bridged.name = "p"
    bridged.default_namespace = ""

    expect(bridged.to_xml).to eq(literal.to_xml)
    expect(bridged.to_xml).not_to include("jats:")
  end

  it "namespace = nil clears the prefix through both call shapes" do
    literal = Leptris::XML::Document.parse(xml).root.children.first
    literal.name = "p"
    literal.namespace = nil

    doc = Leptris::XML::Document.parse(xml)
    bridged = bridged_child(doc)
    bridged.name = "p"
    bridged.namespace = nil

    expect(bridged.to_xml).to eq(literal.to_xml)
    expect(bridged.to_xml).not_to include("jats:")
  end

  it "keeps parity when the native twin is materialized mid-sequence" do
    doc = Leptris::XML::Document.parse(xml)
    el = doc.root.children.first
    el.name = "p"
    doc.native_node.children.first.name # materialize + touch the twin
    el.default_namespace = ""
    expect(el.to_xml).not_to include("jats:")
  end
end
