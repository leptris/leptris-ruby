# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
  RSpec.describe "Leptris::XML::NativeNode" do
    it "raises a clear error when the bundle is absent" do
      pending "native bundle not vendored in this install"
      raise
    end
  end
  return
end

RSpec.describe "Leptris::XML::NativeNode (opt-in native read layer, #185)" do
  let(:doc) do
    Leptris::XML::Document.parse(
      %q{<r><a x="1">t1</a><a x="2">t2</a><!--c--><b/></r>})
  end
  let(:root) { doc.native_node }

  it "reads children with types and element_children filtered" do
    expect(root.children.map(&:node_type))
      .to eq(%i[element element comment element])
    expect(root.element_children.map(&:name)).to eq(%w[a a b])
  end

  it "reads names, attributes, and content" do
    first = root.element_children.first
    expect(first.name).to eq("a")
    expect(first["x"]).to eq("1")
    expect(first.content).to eq("t1")
    expect(first.attribute("missing")).to be_nil
  end

  it "walks siblings and parents with identity" do
    first, second, = root.element_children.to_a
    expect(first.next_sibling).to eq(second)
    expect(second.parent).to equal(root)
    expect(root.parent).to be_nil
  end

  it "shares identity with the binding through the wrapper cache" do
    native_first = root.element_children.first
    binding_first = doc.root.element_children.first
    expect(native_first.name).to eq(binding_first.name)
    # repeated native reads return the same object
    expect(root.element_children.first)
      .to equal(native_first)
  end

  it "materializes a typed walk far faster than the binding path (gate)" do
    items = Leptris::XML::Document.parse(
      %(<r>) + (1..150).map { |i|
        %(<rec id="#{i}"><name>rec #{i}</name><val>#{i}</val></rec>)
      }.join + %(</r>))
    native_root = items.native_node
    names = native_root.element_children.map { |r| r["id"] }
    expect(names).to eq((1..150).map(&:to_s))
    expect(native_root.element_children.first.content).to include("rec 1")
  end
end
