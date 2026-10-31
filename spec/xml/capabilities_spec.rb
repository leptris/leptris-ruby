# frozen_string_literal: true

# leptris-ruby#572: the engine's capability descriptor
# (leptris_capabilities, libleptris 1.9.392+) bridged through FFI.
# The contract (leptris/leptris#1905): bits append, never reorder;
# the binding exposes the raw bitset + descriptor version and
# re-encodes nothing.
RSpec.describe Leptris::XML, '.capabilities' do
  let(:caps) { described_class.capabilities }

  it 'returns a frozen hash' do
    expect(caps).to be_a(Hash)
    expect(caps).to be_frozen
  end

  it 'carries the descriptor version' do
    expect(caps[:descriptor_version]).to eq(1)
  end

  it 'reports the always-served faces' do
    # engine constants (leptris/types.h): bits append per contract
    parse   = 1 << 0
    dom     = 1 << 1
    xpath   = 1 << 2
    xsd     = 1 << 10
    relaxng = 1 << 12
    xslt    = 1 << 14
    expect(caps[:caps] & parse).to eq(parse)
    expect(caps[:caps] & dom).to eq(dom)
    expect(caps[:caps] & xpath).to eq(xpath)
    expect(caps[:caps] & xsd).to eq(xsd)
    expect(caps[:caps] & relaxng).to eq(relaxng)
    expect(caps[:caps] & xslt).to eq(xslt)
  end

  it 'never carries unknown bits beyond the shipped contract' do
    # descriptor version 1 covers bits 0..24 (entity-ref nodes)
    expect(caps[:caps] & ~((1 << 25) - 1)).to eq(0)
  end

  it 'is stable across calls' do
    expect(described_class.capabilities).to eq(caps)
  end
end
