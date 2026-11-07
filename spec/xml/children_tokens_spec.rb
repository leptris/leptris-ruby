# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# leptris-ruby#603 ask 2: the C-side token registry. children_tokens
# is ONE children_ex crossing returning [addrs, kinds, tokens] —
# tokens are frozen [addr, kind] pairs minted through a second
# address-keyed cache on the document (the token lane), so a
# consumer holds identity across calls without the NativeNode
# TypedData mint and without a second crossing to classify
# nil-name rows.
RSpec.describe "Native.children_tokens (#603 ask 2)",
               if: defined?(Leptris::XML::NativeNode) do
  let(:doc) do
    Leptris::XML::Document.parse(
      %(<r><a>one<b/>two</a><c/></r>)
    )
  end

  let(:cols) do
    Leptris::XML::Native.children_tokens(doc.native_node)
  end
  let(:addrs) { cols[0] }
  let(:kinds) { cols[1] }
  let(:tokens) { cols[2] }

  it "returns three parallel arrays of equal length" do
    expect(cols).to be_an(Array)
    expect(cols.size).to eq(3)
    # r, a, "one", b, "two", c — six nodes in preorder
    expect(addrs.size).to eq(6)
    expect(kinds.size).to eq(6)
    expect(tokens.size).to eq(6)
  end

  it "mints tokens as frozen [addr, kind] pairs" do
    tokens.each_with_index do |tok, i|
      expect(tok).to be_an(Array)
      expect(tok).to be_frozen
      expect(tok[0]).to eq(addrs[i])
      expect(tok[1]).to eq(kinds[i])
    end
  end

  it "kinds agree with the walk_addresses kinds column" do
    walk = Leptris::XML::Native.walk_addresses(doc.native_node)
    expect(kinds).to eq(walk[3])
    expect(addrs).to eq(walk[1])
  end

  it "mint-twice returns the SAME token objects (identity across calls)" do
    again = Leptris::XML::Native.children_tokens(doc.native_node)
    tokens.each_with_index do |tok, i|
      expect(again[2][i].equal?(tok)).to be(true),
                                         "token #{i} must be the same object across calls"
    end
  end

  it "mints nothing into the native (TypedData) identity cache" do
    root = doc.native_node
    before = doc.native_cache.size
    Leptris::XML::Native.children_tokens(root)
    expect(doc.native_cache.size).to eq(before),
                                     "the token lane must not register wrappers in native_cache"
  end

  it "root's own token is minted too (children of the doc-root walk)" do
    # The walk starts at the receiver; the receiver itself is row 0
    # with kind 0 (element).
    expect(tokens[0][1]).to eq(0)
    expect(tokens[0][0]).to be_an(Integer)
  end
end
