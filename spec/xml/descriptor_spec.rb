# frozen_string_literal: true

RSpec.describe "Leptris::XML::Descriptor (libleptris 1.9.162, upstream #1039)" do
  let(:xml) do
    %(<catalog version="2.0">) +
      %(<item id="1"><name>first</name><price>1.99</price><opt>a</opt><opt>b</opt></item>) +
      %(<item id="2"><name>second</name><price>2.99</price></item>) +
      %(</catalog>)
  end

  let(:descriptor) do
    Leptris::XML::Descriptor.build(
      name: "catalog",
      attributes: [{ name: "version", kind: :scalar }],
      children: [
        { name: "item", kind: :nested, type_tag: 7, plan: {
          name: "item",
          attributes: [{ name: "id", kind: :scalar }],
          children: [
            { name: "name", kind: :scalar },
            { name: "price", kind: :scalar },
            { name: "opt", kind: :collection },
            { name: "ghost", kind: :scalar },
          ] } },
      ])
  end

  it "materializes the whole subtree in one walk" do
    result = descriptor.walk(Leptris::XML::Document.parse(xml).root)
    expect(result.kind).to eq(:element)
    expect(result.count).to eq(2)
    expect(result.attribute("version")).to eq("2.0")
    tree = result.to_ruby
    expect(tree[:attributes]).to eq("version" => "2.0")
    item1, item2 = tree[:children]
    expect(item1).to include(name: "item", type_tag: 7,
                             attributes: { "id" => "1" })
    expect(item1[:children]).to eq(["first", "1.99", %w[a b]])
    expect(item2[:children]).to eq(["second", "2.99"])
  end

  it "skips children the plan does not describe" do
    tree = descriptor.walk(Leptris::XML::Document.parse(xml).root).to_ruby
    expect(tree[:children].flat_map { |i| i[:children] })
      .not_to include(a_string_matching(/ghost/))
  end

  it "is reusable across documents" do
    other = Leptris::XML::Document.parse(
      %(<catalog version="9"><item id="x"><name>later</name></item></catalog>))
    tree = descriptor.walk(other.root).to_ruby
    expect(tree[:attributes]).to eq("version" => "9")
    expect(tree[:children].first[:children]).to eq(["later"])
  end

  it "carries callback positions that match Node#byte_offset" do
    doc = Leptris::XML::Document.parse(
      %(<r>lead <cb>hi</cb> mid <b>bold</b> tail</r>))
    d = Leptris::XML::Descriptor.build(
      name: "r", flags: [:mixed_content],
      children: [
        { name: "cb", kind: :callback, type_tag: 9 },
        { name: "b", kind: :content },
      ])
    callback, runs, = d.walk(doc.root).to_ruby[:children]
    expect(callback).to eq(value: "hi",
                           position: doc.root.at("cb").byte_offset,
                           type_tag: 9)
    expect(runs).to eq(["lead ", " mid ", " tail"]) # text runs, doc order
  end

  it "binds namespaced children through nested plans with ns:" do
    doc = Leptris::XML::Document.parse(
      %(<r xmlns:m="urn:m"><m:deep>v</m:deep></r>))
    d = Leptris::XML::Descriptor.build(
      name: "r",
      children: [
        { name: "deep", kind: :nested, plan: {
          name: "deep", ns: { exact: "urn:m" } } },
      ])
    tree = d.walk(doc.root).to_ruby
    expect(tree[:children].first[:name]).to eq("deep")
  end

  it "rejects unknown kinds and ns shapes at the boundary" do
    expect { Leptris::XML::Descriptor.build(name: "r", children: [{ name: "x", kind: :bogus }]) }
      .to raise_error(ArgumentError, /kind must be one of/)
    expect { Leptris::XML::Descriptor.build(name: "r", ns: :weird) }
      .to raise_error(ArgumentError, /ns must be :none/)
  end

  it "exposes raw serialized subtrees and Node#byte_offset" do
    doc = Leptris::XML::Document.parse(%(<r><n><![CDATA[x<y]]></n></r>))
    d = Leptris::XML::Descriptor.build(
      name: "r", children: [{ name: "n", kind: :raw }])
    expect(d.walk(doc.root).to_ruby[:children])
      .to eq([%(<n><![CDATA[x<y]]></n>)])
    expect(doc.root.at("n").byte_offset).to eq(3)
  end
end
