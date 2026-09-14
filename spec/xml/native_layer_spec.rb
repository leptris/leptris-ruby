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

RSpec.describe "Native builder factories (#149)" do
  it "creates elements and text without the wrap_fresh path" do
    doc = Leptris::XML::Document.create
    root = doc.native_create_element("r")
    doc.native_root = root
    child = doc.native_create_element("field")
    text = doc.native_create_text("value")
    child.add_child(text)
    root.add_child(child)
    expect(root.element_children.map(&:name)).to eq(%w[field])
    expect(root.element_children.first.content).to eq("value")
  end

  it "create_child fuses create+append" do
    doc = Leptris::XML::Document.create
    root = doc.native_create_element("r")
    doc.native_root = root
    a = root.create_child("a")
    b = root.create_child("b")
    expect(root.element_children.map(&:name)).to eq(%w[a b])
    expect(a.parent.equal?(root)).to be(true)
  end

  it "keeps binding Document#root working after native_root=" do
    doc = Leptris::XML::Document.create
    root = doc.native_create_element("r")
    doc.native_root = root
    expect(doc.root).to be_a(Leptris::XML::Element)
    expect(doc.root.name).to eq("r")
    expect(doc.native_node.name).to eq("r")
  end
end

RSpec.describe "NativeNode surface completion (TODO.perf/05)" do
  it "reads the attribute hash in one C walk (string values)" do
    doc = Leptris::XML::Document.parse(%q{<rec id="7" sku="S7">x</rec>})
    rec = doc.native_node
    expect(rec.attributes).to eq("id" => "7", "sku" => "S7")
    expect(rec.attributes.keys).to eq(%w[id sku])
  end

  it "reads line and byte_offset with binding parity" do
    doc = Leptris::XML::Document.parse(%q{<r><rec id="7">x</rec></r>})
    native_rec = doc.native_node.element_children.first
    binding_rec = doc.root.element_children.first
    expect(native_rec.line).to eq(binding_rec.line)
    expect(native_rec.byte_offset).to eq(binding_rec.byte_offset)
    expect(native_rec.byte_offset).to be > 0
  end
end

RSpec.describe "bulk paths never truncate (#202)" do
  it "returns every child past the 512 batch floor" do
    [511, 512, 513, 600, 1000].each do |n|
      doc = Leptris::XML::Document.parse(
        "<r>" + (1..n).map { |i| i.even? ? "<c/>" : "t" }.join + "</r>")
      expect(doc.native_node.children.size).to eq(n)
      expect(doc.root.children.size).to eq(n)
      expect(doc.native_node.element_children.size)
        .to eq((1..n).count(&:even?))
    end
  end

  it "materializes xpath results past the floor" do
    doc = Leptris::XML::Document.parse("<r>" + ("<e/>" * 800) + "</r>")
    expect(doc.xpath("//e").size).to eq(800)
  end
end

RSpec.describe "NativeNode#document (moxml #213)" do
  it "returns the owning binding Document for self and descendants" do
    doc = Leptris::XML::Document.parse(%q{<r><a/></r>})
    root = doc.native_node
    expect(root.document).to equal(doc)
    expect(root.element_children.first.document).to equal(doc)
  end
end
