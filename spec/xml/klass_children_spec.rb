# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# leptris-ruby#246: klass-propagating reads. A consumer subclass
# (minted via NativeNode.from's klass injection) installs a
# child-klass map once; children/element_children/next_sibling/
# parent then mint the mapped subclass per node kind — the child
# arrives already BEING the consumer's wrapper.
RSpec.describe "klass-propagating native reads", if: defined?(Leptris::XML::NativeNode) do
  let(:element_klass) { Class.new(Leptris::XML::NativeNode) }
  let(:text_klass) { Class.new(Leptris::XML::NativeNode) }

  def consumer_root(doc)
    map = [element_klass, text_klass, nil, nil, nil]
    element_klass.install_child_klasses(map)
    text_klass.install_child_klasses(map)
    element_klass.from(doc, doc.native_node)
  end

  it "mints children as the mapped subclass per kind" do
    doc = Leptris::XML::Document.parse(%q{<r><e a="1"/><e/>t</r>})
    root = consumer_root(doc)
    kids = root.children
    expect(kids[0]).to be_instance_of(element_klass)
    expect(kids[0]["a"]).to eq("1")
    expect(kids[1]).to be_instance_of(element_klass)
    expect(kids[2]).to be_instance_of(text_klass)
    expect(kids[2].content).to eq("t")
  end

  it "mints element_children through the element slot" do
    doc = Leptris::XML::Document.parse(%q{<r><e/>t<!--c--><e/></r>})
    root = consumer_root(doc)
    expect(root.element_children).to all(be_instance_of(element_klass))
    expect(root.element_children.map(&:name)).to eq(%w[e e])
  end

  it "round-trips identity through the shared address cache" do
    doc = Leptris::XML::Document.parse(%q{<r><e/></r>})
    root = consumer_root(doc)
    expect(root.children.first).to equal(root.children.first)
    expect(root.children.first).to equal(root.element_children.first)
  end

  it "propagates through next_sibling and parent" do
    doc = Leptris::XML::Document.parse(%q{<r><a/>t<b/></r>})
    root = consumer_root(doc)
    first = root.children[0]
    text = first.next_sibling
    expect(text).to be_instance_of(text_klass)
    expect(text.next_sibling).to be_instance_of(element_klass)
    expect(text.parent).to be_instance_of(element_klass)
    expect(text.parent.address).to eq(root.address)
  end

  it "keeps the base class for map-less callers" do
    doc = Leptris::XML::Document.parse(%q{<r><e/>t</r>})
    native = doc.native_node
    expect(native.children.map(&:class).uniq)
      .to eq([Leptris::XML::NativeNode])
    expect(native.next_sibling).to be_nil
    expect(native.children.first.parent.class)
      .to eq(Leptris::XML::NativeNode)
  end

  it "rejects non-NativeNode entries at install time" do
    expect { element_klass.install_child_klasses([Object]) }
      .to raise_error(TypeError)
    expect { element_klass.install_child_klasses("nope") }
      .to raise_error(TypeError)
  end

  it "keeps mutation coherence on subclass instances" do
    doc = Leptris::XML::Document.parse(%q{<r><e sku="S7">t</e></r>})
    root = consumer_root(doc)
    e = root.children[0]
    first = e["sku"]
    expect(e["sku"]).to equal(first)
    doc.root.element_children.first["sku"] = "CHANGED"
    expect(e["sku"]).to eq("CHANGED")
  end

  it "raises ReadOnlyError through the subclass face" do
    doc = Leptris::XML::Document.parse(%q{<r><e/></r>})
    root = consumer_root(doc)
    doc.readonly!
    expect {
      root.append_child(Leptris::XML::NativeNode.create_text(doc, "x"))
    }.to raise_error(Leptris::XML::ReadOnlyError)
  end
end
