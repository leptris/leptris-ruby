# frozen_string_literal: true

# leptris-ruby#586 ask 2: attribute_rows_native passes the raw
# Integer attribute addresses — no per-attribute FFI::Pointer mint
# on read-only callers (~2M Pointers on the 103 MB XMI walk). The
# Pointer is minted lazily, on the first namespace read; hand-built
# Attrs that receive a Pointer keep working unchanged.
RSpec.describe Leptris::XML::Attr, 'lazy c_handle from attribute_rows_native' do
  let(:xml) { '<root xmlns:x="urn:x" x:a="1" b="2"/>' }
  let(:doc) { Leptris::XML::Document.parse(xml) }
  let(:rows) { doc.root.attribute_rows_native }

  it 'carries the raw Integer address, not a Pointer' do
    expect(rows.map(&:name)).to eq(%w[x:a b])
    expect(rows[0].instance_variable_get(:@c_handle)).to be_an(Integer)
    expect(rows[1].instance_variable_get(:@c_handle)).to be_an(Integer)
  end

  it 'mints the Pointer on first namespace read and resolves the URI' do
    expect(rows[0].namespace_uri).to eq('urn:x')
    expect(rows[0].instance_variable_get(:@c_handle)).to be_a(FFI::Pointer)
  end

  it 'a no-namespace attribute reads nil and stays an Integer' do
    expect(rows[1].namespace_uri).to be_nil
  end

  it 'keeps values and mutation semantics' do
    expect(rows[0].value).to eq('1')
    rows[1].value = '9'
    expect(doc.root['b']).to eq('9')
  end

  it 'hand-built Attrs with a Pointer keep the eager path' do
    a = described_class.new('p', 'v', doc.root,
                            c_handle: FFI::Pointer.new(1))
    expect(a.instance_variable_get(:@c_handle)).to be_a(FFI::Pointer)
  end
end
