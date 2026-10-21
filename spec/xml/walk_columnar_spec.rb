# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# leptris-ruby#527: columnar preorder walk — the moxml cold walk
# crossed FFI once per element (children_read + name_read per
# node); walk_columnar returns a whole subtree's walk data (names,
# node handles, depths) in ONE crossing. Handles are NativeNodes
# minted through the registered klasses/doc-klass map with
# native-cache identity; element names are frozen (interned).
RSpec.describe "Native.walk_columnar (#527)",
               if: defined?(Leptris::XML::NativeNode) do
  let(:doc) do
    Leptris::XML::Document.parse(
      %(<r><a>one<b/>two</a><c/><d x="1"><e/></d></r>))
  end

  let(:cols) { Leptris::XML::Native.walk_columnar(doc.native_node) }
  let(:names) { cols[0] }
  let(:handles) { cols[1] }
  let(:depths) { cols[2] }

  # preorder: r, a, "one", b, "two", c, d, e — 8 nodes
  it "returns three parallel arrays of equal length" do
    expect(cols).to be_an(Array)
    expect(cols.size).to eq(3)
    expect(names.size).to eq(8)
    expect(handles.size).to eq(8)
    expect(depths.size).to eq(8)
  end

  it "walks preorder with names and depths" do
    expect(names).to eq(["r", "a", nil, "b", nil, "c", "d", "e"])
    expect(depths).to eq([0, 1, 2, 2, 2, 1, 1, 2])
  end

  it "freezes element names" do
    expect(names.compact).to all(be_frozen)
  end

  it "mints NativeNode handles that read through" do
    expect(handles).to all(be_a(Leptris::XML::NativeNode))
    expect(handles[0].name).to eq("r")
    expect(handles[1].name).to eq("a")
    expect(handles[2].content).to eq("one")
    expect(handles[5].name).to eq("c")
    expect(handles[6].attribute("x")).to eq("1")
  end

  it "preserves native-cache identity across crossings" do
    root = doc.native_node
    cols = Leptris::XML::Native.walk_columnar(root)
    expect(cols[1][0]).to equal(root)
    expect(cols[1][1]).to equal(root.children_read.first)
    again = Leptris::XML::Native.walk_columnar(root)
    expect(again[1]).to eq(cols[1])
  end

  it "mints the registered doc-klass map entries" do
    el = Class.new(Leptris::XML::NativeNode)
    tx = Class.new(Leptris::XML::NativeNode)
    doc.register_wrapper_klasses([el, tx, nil, nil, nil])
    # The root wrapper arrives through the same #340 machinery the
    # walk cache uses: NativeNode.from stamps a plain NativeNode
    # and the native cache wins by identity law (pre-existing
    # #from behavior, unchanged here), so seed the root through
    # the visit mint before walking.
    root = nil
    doc.root.visit { |n, _| root ||= n }
    cols2 = Leptris::XML::Native.walk_columnar(root)

    expect(cols2[1].count { |n| n.instance_of?(el) }).to eq(6)
    expect(cols2[1].count { |n| n.instance_of?(tx) }).to eq(2)
    expect(cols2[1]).to all(be_a(Leptris::XML::NativeNode))
  end

  it "handles a leaf and a text root" do
    leaf = Leptris::XML::Document.parse(%(<solo/>))
    one = Leptris::XML::Native.walk_columnar(leaf.native_node)
    expect(one[0]).to eq(["solo"])
    expect(one[2]).to eq([0])

    only_text = Leptris::XML::Native.walk_columnar(handles[2])
    expect(only_text[0]).to eq([nil])
    expect(only_text[2]).to eq([0])
  end
end
