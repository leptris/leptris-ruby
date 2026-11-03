# frozen_string_literal: true

# leptris-ruby#587 ask 2: the per-document identity cache
# (@native_cache — binding Node.wrap + NativeNode minting) retains
# every wrapper for the document's lifetime; a parse -> hydrate ->
# discard lane releases it only at document GC. clear_native_cache
# is the documented drop point: after it, surviving wrappers stay
# valid (they carry their own document + address) but new crossings
# mint fresh wrappers — the identity contract ends where the host
# says it ends. Document#free drops the cache too, releasing the
# wrapper set at free time instead of GC time.
RSpec.describe Leptris::XML::Document, '#clear_native_cache' do
  let(:xml) { '<root><a>1</a><b>2</b></root>' }
  let(:doc) { Leptris::XML::Document.parse(xml) }

  it 'drops the retained wrapper set (new crossings mint anew)' do
    doc.native_node
    expect(doc.native_cache).not_to be_empty

    doc.clear_native_cache

    expect(doc.native_cache).to be_empty
  end

  it 'returns self for chaining' do
    expect(doc.clear_native_cache).to equal(doc)
  end

  it 'is idempotent on a fresh document' do
    expect { doc.clear_native_cache }.not_to raise_error
    expect(doc.native_cache).to be_empty
  end

  it 'surviving wrappers stay valid after the drop' do
    node = doc.native_node
    doc.clear_native_cache
    expect(node.document).to equal(doc)
    expect(node.name).to eq('root')
  end

  it 'Document#free releases the cache at free time' do
    doc.native_node
    expect(doc.native_cache).not_to be_empty

    doc.free

    expect(doc.instance_variable_get(:@native_cache)).to be_nil
  end
end
