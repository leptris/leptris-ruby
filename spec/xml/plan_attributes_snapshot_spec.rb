# frozen_string_literal: true

RSpec.describe "Leptris::XML::PlanValue#attributes_snapshot" do
  let(:xml) do
    %(<catalog version="2.0" lang="en">) +
      %(<item id="1" ref="abc"><name>first</name></item>) +
      %(<item id="2"><name>second</name></item>) +
      %(</catalog>)
  end

  let(:descriptor) do
    Leptris::XML::Descriptor.build(
      name: "catalog",
      attributes: [{ name: "version", kind: :scalar },
                    { name: "lang", kind: :scalar }],
      children: [
        { name: "item", kind: :nested, type_tag: 7, plan: {
          name: "item",
          attributes: [{ name: "id", kind: :scalar },
                        { name: "ref", kind: :scalar }],
          children: [{ name: "name", kind: :scalar }],
        } },
      ],
    )
  end

  let(:root) { descriptor.walk(Leptris::XML::Document.parse(xml).root) }

  it "returns all bound attributes in one hash" do
    expect(root.attributes_snapshot).to eq("version" => "2.0", "lang" => "en")
  end

  it "agrees with the per-name attribute reads on children" do
    _names, _tags, children = root.children_snapshot

    expect(children[0].attributes_snapshot).to eq("id" => "1", "ref" => "abc")
    expect(children[1].attributes_snapshot).to eq("id" => "2")
  end

  it "returns an empty hash when no attributes are bound" do
    doc = Leptris::XML::Document.parse(%(<p>text</p>))
    descriptor = Leptris::XML::Descriptor.build(
      name: "p",
      children: [{ name: "__content__1", kind: :content }])

    expect(descriptor.walk(doc.root).attributes_snapshot).to eq({})
  end

  it "returns an empty hash for a scalar value" do
    _names, _tags, children = root.children_snapshot
    scalar = children[0].at(0)

    expect(scalar.attributes_snapshot).to eq({})
  end

  it "handles values larger than the initial buffer guess" do
    long = "x" * 500
    doc = Leptris::XML::Document.parse(%(<e a="#{long}"/>))
    descriptor = Leptris::XML::Descriptor.build(
      name: "e",
      attributes: [{ name: "a", kind: :scalar }])

    expect(descriptor.walk(doc.root).attributes_snapshot)
      .to eq("a" => long)
  end

  it "returns UTF-8-encoded names and values like the per-name reader" do
    doc = Leptris::XML::Document.parse(
      %(<e prix="café" texte="naïve"/>))
    descriptor = Leptris::XML::Descriptor.build(
      name: "e",
      attributes: [{ name: "prix", kind: :scalar },
                   { name: "texte", kind: :scalar }])

    attrs = descriptor.walk(doc.root).attributes_snapshot
    expect(attrs.keys.map(&:encoding).uniq).to eq([Encoding::UTF_8])
    expect(attrs.values.map(&:encoding).uniq).to eq([Encoding::UTF_8])
    expect(attrs["prix"]).to eq("café")
  end

  it "crosses once per node, not once per attribute" do
    _names, _tags, children = root.children_snapshot
    child = children[0]

    child.reset_crossings!
    child.attributes_snapshot

    expect(child.crossings).to be < 4
  end
end
