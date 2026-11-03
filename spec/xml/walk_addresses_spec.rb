# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# leptris-ruby#587: raw-address columnar walk — the identity-free
# read lane. Same preorder/depths contract as walk_columnar (#527),
# but the handles lane carries RAW NODE ADDRESSES as Integers: no
# NativeNode mints, no identity-cache writes, addresses are
# immediates in CRuby. Read-only consumers resolve names, text, and
# attribute packets through the address-keyed faces (fast_name,
# fast_element_text, attribute_pairs).
RSpec.describe "Native.walk_addresses (#587)",
               if: defined?(Leptris::XML::NativeNode) do
  let(:doc) do
    Leptris::XML::Document.parse(
      %(<r><a>one<b/>two</a><c/><d x="1"><e/></d></r>))
  end

  let(:cols) { Leptris::XML::Native.walk_addresses(doc.native_node) }
  let(:names) { cols[0] }
  let(:addrs) { cols[1] }
  let(:depths) { cols[2] }

  it "returns three parallel arrays of equal length" do
    expect(cols).to be_an(Array)
    expect(cols.size).to eq(3)
    expect(names.size).to eq(8)
    expect(addrs.size).to eq(8)
    expect(depths.size).to eq(8)
  end

  it "walks preorder with interned names and depths" do
    expect(names).to eq(["r", "a", nil, "b", nil, "c", "d", "e"])
    expect(names.all? { |n| n.nil? || n.frozen? }).to be(true)
    expect(depths).to eq([0, 1, 2, 2, 2, 1, 1, 2])
  end

  it "carries raw addresses as Integers, not wrapper objects" do
    expect(addrs).to all(be_an(Integer))
    expect(addrs.uniq.size).to eq(addrs.size), "addresses are unique"
  end

  it "serves reads through the address-keyed faces" do
    addrs.each_with_index do |addr, i|
      next if names[i].nil?

      expect(Leptris::XML::Native.fast_name(addr)).to eq(names[i])
    end
    expect(Leptris::XML::Native.fast_element_text(addrs[1])).to eq("onetwo")
    d_addr = addrs[names.index("d")]
    expect(Leptris::XML::Native.attribute_pairs(doc, d_addr))
      .to eq(["x", "1"])
  end

  it "mints nothing into the document identity cache" do
    root = doc.native_node # mint the receiver, as any caller would
    cache_before = doc.native_cache.size
    Leptris::XML::Native.walk_addresses(root)
    expect(doc.native_cache.size).to eq(cache_before),
      "the walk must not register any node in the identity cache"
  end

  it "agrees with walk_columnar on shape" do
    col = Leptris::XML::Native.walk_columnar(doc.native_node)
    expect(names).to eq(col[0])
    expect(depths).to eq(col[2])
    expect(addrs).to all(be_an(Integer))
  end

  it "reflects mutations made through wrapper handles" do
    b_addr = addrs[names.index("b")]
    expect(Leptris::XML::Native.fast_element_text(b_addr)).to eq("")
    b_wrapper = doc.root.children.first.children.find { |c| c.name == "b" }
    b_wrapper << "tail"
    expect(Leptris::XML::Native.fast_element_text(b_addr)).to eq("tail")
  end
end
