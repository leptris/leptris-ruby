# frozen_string_literal: true

RSpec.describe "Leptris::XML::PlanValue#children_snapshot" do
  let(:xml) do
    %(<catalog version="2.0">) +
      %(<item id="1"><name>first</name></item>) +
      %(<item id="2"><name>second</name></item>) +
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
          children: [{ name: "name", kind: :scalar }],
        } },
      ],
    )
  end

  let(:root) { descriptor.walk(Leptris::XML::Document.parse(xml).root) }

  it "returns parallel name, tag, and child arrays" do
    names, tags, children = root.children_snapshot

    expect(names).to eq(%w[item item])
    expect(tags).to eq([7, 7])
    expect(children.map { |c| c.attribute("id") }).to eq(%w[1 2])
  end

  it "keeps content runs out of the child list under this plan shape" do
    doc = Leptris::XML::Document.parse(%(<p>text<a/>more</p>))
    descriptor = Leptris::XML::Descriptor.build(
      name: "p",
      children: [{ name: "__content__1", kind: :content },
                 { name: "a", kind: :scalar }])

    names, _tags, _children = descriptor.walk(doc.root).children_snapshot

    # Text is carried by the content row, not minted as a NULL-name
    # kid; the SIZE_MAX offsets protocol stays reserved for walk
    # shapes that do emit them (lutaml-model's group_children guard).
    expect(names).to eq(["a"])
  end

  it "agrees with the per-child at/name/type_tag enumeration" do
    names, tags, _children = root.children_snapshot
    count = root.count

    count.times do |i|
      child = root.at(i)
      expect(names[i]).to eq(child.name)
      expect(tags[i]).to eq(child.type_tag)
    end
  end

  it "crosses once per subtree, not once per child accessor" do
    root.reset_crossings!
    root.children_snapshot

    expect(root.crossings).to be < 4
  end
end
