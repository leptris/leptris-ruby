# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# #340: C-side wrapper mint for construction and cold walks.
# Document#register_wrapper_klasses installs a per-kind klass map;
# the C walk cache (trav/visit) and the create faces mint those
# klasses directly — TypedData path, native-cache identity — so
# consumers receive their own contract-carrying nodes straight
# from the crossing. Unregistered documents keep the binding
# wrapper classes.
RSpec.describe "Document wrapper-klass registration (#340)",
               if: defined?(Leptris::XML::NativeNode) do
  let(:el_klass) { Class.new(Leptris::XML::NativeNode) }
  let(:tx_klass) { Class.new(Leptris::XML::NativeNode) }
  let(:doc) do
    d = Leptris::XML::Document.parse("<r><a>one</a><b>two</b></r>")
    d.register_wrapper_klasses([el_klass, tx_klass, nil, nil, nil])
    d
  end

  it "validates entries as nil or NativeNode subclasses" do
    expect { doc.register_wrapper_klasses([String]) }
      .to raise_error(TypeError)
    expect { doc.register_wrapper_klasses(Array.new(6) { el_klass }) }
      .to raise_error(ArgumentError)
  end

  it "mints the registered klasses from the C walk" do
    classes = []
    doc.root.visit { |n, _| classes << n.class }
    expect(classes).to all(be < Leptris::XML::NativeNode)
    # two-event visit: elements enter+leave; text yields once
    expect(classes.count(el_klass)).to eq(6)  # r, a, b
    expect(classes.count(tx_klass)).to eq(2)  # one, two
  end

  it "preserves node identity across walks" do
    first = []
    doc.root.visit { |n, _| first << n }
    second = []
    doc.root.visit { |n, _| second << n }
    expect(second).to eq(first)
  end

  it "reads through the consumer wrappers" do
    texts = []
    doc.root.visit do |n, _|
      texts << n.content if n.instance_of?(tx_klass)
    end
    expect(texts).to eq(%w[one two])
  end

  it "returns the registered klass from the wrapped create face" do
    built = Leptris::XML::Native.create_element_with_attrs_wrapped(
      doc, doc.root.c_ptr.address, "book", ["id", "1", "k", "v"])
    expect(built).to be_instance_of(el_klass)
    expect(built["id"]).to eq("1")
    expect(built["k"]).to eq("v")
  end

  it "attaches created nodes under the parent" do
    Leptris::XML::Native.create_element_with_attrs_wrapped(
      doc, doc.root.c_ptr.address, "book", ["id", "7"])
    names = []
    doc.root.visit { |n, _| names << n.name rescue nil }
    expect(names).to include("book")
  end

  it "keeps unregistered documents on the binding classes" do
    plain = Leptris::XML::Document.parse("<r><a/></r>")
    classes = []
    plain.root.visit { |n, _| classes << n.class }
    expect(classes).to all(be <= Leptris::XML::Node)
    expect(classes.uniq).to eq([Leptris::XML::Element])

    built = Leptris::XML::Native.create_element_with_attrs_wrapped(
      plain, plain.root.c_ptr.address, "x", ["a", "1"])
    expect(built).to be_instance_of(Leptris::XML::Element)
  end

  it "shares identity between create and walk for the same node" do
    built = Leptris::XML::Native.create_element_with_attrs_wrapped(
      doc, doc.root.c_ptr.address, "dup", [])
    seen = nil
    doc.root.visit { |n, _| seen = n if n.name == "dup" }
    expect(seen).to equal(built)
  end
end
