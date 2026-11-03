# frozen_string_literal: true

# leptris-ruby#586 ask 1: the flat packet attribute face. One C
# crossing returns [name1, value1, name2, value2, ...] — no Attr
# wrappers, no FFI::Pointer per attribute, no slice arrays, no
# per-element memo, nothing written to the identity cache. Names are
# interned (identity-stable across calls); values are fresh strings.
RSpec.describe Leptris::XML::Native, '.attribute_packet' do
  let(:xml) { '<root a="1" b="2" xlink:href="u"/>' }
  let(:doc) { Leptris::XML::Document.parse(xml) }
  let(:root_addr) { doc.root.c_address }

  it 'returns one flat [name, value, ...] array in document order' do
    packet = described_class.attribute_packet(doc, root_addr)
    expect(packet).to be_an(Array)
    expect(packet.length).to eq(6)
    expect(packet[0]).to eq('a')
    expect(packet[1]).to eq('1')
    expect(packet[2]).to eq('b')
    expect(packet[3]).to eq('2')
    expect(packet[4]).to eq('xlink:href')
    expect(packet[5]).to eq('u')
  end

  it 'interns names across calls' do
    p1 = described_class.attribute_packet(doc, root_addr)
    p2 = described_class.attribute_packet(doc, root_addr)
    expect(p1[0]).to equal(p2[0])
    expect(p1[4]).to equal(p2[4])
  end

  it 'values are fresh strings per call' do
    p1 = described_class.attribute_packet(doc, root_addr)
    p2 = described_class.attribute_packet(doc, root_addr)
    expect(p1[1]).not_to equal(p2[1])
  end

  it 'mints nothing into the identity cache' do
    doc.native_node
    before = doc.native_cache.size
    described_class.attribute_packet(doc, root_addr)
    expect(doc.native_cache.size).to eq(before)
  end

  it 'returns [] for an element with no attributes' do
    doc2 = Leptris::XML::Document.parse('<bare/>')
    expect(described_class.attribute_packet(doc2, doc2.root.c_address))
      .to eq([])
  end
end
