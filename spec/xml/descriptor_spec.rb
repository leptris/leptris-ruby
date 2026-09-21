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

RSpec.describe "Leptris::XML::Descriptor typed scalars + materialize (#230's fused-consumer contract)" do
  let(:descriptor) do
    Leptris::XML::Descriptor.build(
      name: "catalog",
      attributes: [{ name: "version", kind: :scalar, type: :integer }],
      children: [
        { name: "item", kind: :nested, plan: {
            name: "item",
            attributes: [
              { name: "id", kind: :scalar, type: :integer },
              { name: "weight", kind: :scalar, type: :float },
              { name: "in_stock", kind: :scalar, type: :boolean },
            ],
            children: [
              { name: "price", kind: :scalar, type: :float },
              { name: "title", kind: :scalar },
              { name: "note", kind: :scalar, type: :integer },
            ] } },
      ])
  end

  let(:xml) do
    %(<catalog version="2"><item id="7" weight="1.25" in_stock="true") +
      %(><price>9.99</price><title>Book</title><note>n/a</note></item></catalog>)
  end

  it "casts element and attribute scalars per the row's type" do
    tree = descriptor.walk(Leptris::XML::Document.parse(xml).root).to_ruby
    expect(tree[:attributes]["version"]).to eq(2)
    item = tree[:children].first
    expect(item[:attributes]).to eq(
      "id" => 7, "weight" => 1.25, "in_stock" => true)
    price, title, note = item[:children]
    expect(price).to eq(9.99)
    expect(title).to eq("Book")
    expect(note).to eq("n/a") # lenient: unparseable int falls back
  end

  it "keeps #string_value raw regardless of tag" do
    root = descriptor.walk(Leptris::XML::Document.parse(xml).root)
    price_scalar = root.at(0).at(0) # item element's first child row
    expect(price_scalar.string_value).to eq("9.99")
  end

  it "rejects unknown types at the boundary" do
    expect {
      Leptris::XML::Descriptor.build(
        name: "r", children: [{ name: "x", kind: :scalar, type: :bogus }])
    }.to raise_error(ArgumentError, /type must be one of/)
  end

  it "materializes from source bytes in one call, standalone from the document" do
    fused = descriptor.materialize(xml)
    parsed = descriptor.walk(Leptris::XML::Document.parse(xml).root)
    expect(fused.to_ruby).to eq(parsed.to_ruby)
    expect(fused.to_ruby[:children].first[:attributes]["id"]).to eq(7)
  end

  it "rejects rootless sources at parse (the no-root guard is defensive)" do
    expect { descriptor.materialize("<!-- comment only -->") }
      .to raise_error(Leptris::XML::ParseError)
  end
end

RSpec.describe "Leptris::XML.PlanValue#as_kwarg_hash (#298's bulk dispatch floor)" do
  let(:descriptor) do
    Leptris::XML::Descriptor.build(
      name: "row",
      attributes: [
        { name: "id", kind: :scalar, type: :integer },
        { name: "ts", kind: :scalar, type: :string },
      ],
      children: [
        { name: "name", kind: :scalar },
        { name: "price", kind: :scalar, type: :float },
        { name: "active", kind: :scalar, type: :boolean },
      ])
  end

  let(:row_xml) do
    %(<row id="7" ts="2026-09-20T12:00:00Z"><name>Item</name>) +
      %(<price>3.99</price><active>true</active></row>)
  end

  it "yields the per-row kwarg hash in one Ruby method call" do
    result = descriptor.materialize(row_xml)
    hash = result.as_kwarg_hash
    expect(hash.keys).to contain_exactly(:name, :type_tag, :attributes, :children)
    expect(hash[:attributes]).to eq("id" => 7, "ts" => "2026-09-20T12:00:00Z")
    expect(hash[:children]["name"]).to eq("Item")
    expect(hash[:children]["price"]).to eq(3.99)
    expect(hash[:children]["active"]).to be(true)
  end

  it "counts FFI accessor crossings on the result handle" do
    result = descriptor.materialize(row_xml)
    result.reset_crossings!
    result.as_kwarg_hash
    expect(result.crossings).to be > 0
  end

  describe "the 5k-row ISO fixture (#298.1 — crossings floor)" do
    let(:iso) do
      rows = (0...5000).map do |i|
        %(<row id="#{i}" ts="2026-09-20T12:00:00Z"><name>Item #{i}</name>) +
          %(<price>#{i}.99</price><active>true</active></row>)
      end
      %(<?xml version="1.0"?><iso>) + rows.join + %(</iso>)
    end

    let(:iso_descriptor) do
      Leptris::XML::Descriptor.build(
        name: "iso",
        children: [{ name: "row", kind: :collection, plan: {
          name: "row",
          attributes: [{ name: "id", kind: :scalar, type: :integer }],
          children: [{ name: "name", kind: :scalar }] } }])
    end

    it "materialize + bulk face on 5000 rows: ~5 FFI crossings per row" do
      result = iso_descriptor.materialize(iso)
      result.reset_crossings!
      result.as_kwarg_hash
      per_row = result.crossings / 5000.0
      # Documented floor: the engine emits collection items as
      # scalars; the bulk face crosses ≈4/row (at + type_tag +
      # typed accessor + string fallback). In-pass fusion
      # (leptris#1269) already removed the parse/walk legs; a
      # native bulk-fields call would collapse the rest.
      expect(per_row).to be_within(0.5).of(4.0)
      expect(per_row).to be < 6
    end
  end
end

RSpec.describe "Leptris::XML::Descriptor plan-ABI wiring (#1272/#1273/#1269 — engine lang/plan-abi-1272)" do
  # #1272: same-wire-name rows with different predicates partition
  # the match space exclusively; AND across pairs.
  describe "attribute-predicate rows" do
    let(:descriptor) do
      Leptris::XML::Descriptor.build(
        name: "r",
        children: [
          { name: "item", kind: :collection, when: { "kind" => "a" },
            plan: { name: "item",
                    attributes: [{ name: "kind", kind: :scalar }],
                    children: [{ name: "name", kind: :scalar }] } },
          { name: "item", kind: :collection, when: { "kind" => "b" },
            plan: { name: "item",
                    attributes: [{ name: "kind", kind: :scalar }],
                    children: [{ name: "name", kind: :scalar }] } },
        ])
    end

    let(:xml) do
      %(<r>) +
        %(<item kind="a">alpha</item>) +
        %(<item kind="b">beta</item>) +
        %(<item kind="a">gamma</item>) +
        %(
</r>)
    end

    it "partitions same-name siblings by predicate, exclusively" do
      tree = descriptor.materialize(xml).to_ruby
      children = tree[:children]
      a_rows = children[0]
      b_rows = children[1]
      # each collection holds only its own partition
      expect(a_rows).to eq(["alpha", "gamma"])
      expect(b_rows).to eq(["beta"])
    end

    it "rejects nil expected values at the boundary" do
      expect {
        Leptris::XML::Descriptor.build(
          name: "r", children: [{ name: "x", kind: :scalar, when: { "k" => nil } }])
      }.to raise_error(ArgumentError, /non-nil/)
    end
  end

  # #1273: document-order identity
  describe "order identity" do
    let(:xml) { %(<r><a>1</a>plain<b>2</b></r>) }
    let(:descriptor) do
      Leptris::XML::Descriptor.build(
        name: "r", flags: [:order_spine],
        children: [
          { name: "a", kind: :scalar },
          { name: "b", kind: :scalar },
        ])
    end

    it "exposes node_kind and order_index on rows" do
      result = descriptor.materialize(xml)
      a = result.at(0)
      b = result.at(1)
      expect(a.order_index).to be < b.order_index
      expect([a.order_index, b.order_index].uniq.length).to eq(2)
    end
  end

  # #1269a: in-pass type execution
  describe "in-pass typed values" do
    let(:xml) { %(<r><n>42</n><p>2.5</p><ok>true</ok><bad>zzz</bad></r>) }
    let(:descriptor) do
      Leptris::XML::Descriptor.build(
        name: "r", children: [
          { name: "n", kind: :scalar, type: :integer },
          { name: "p", kind: :scalar, type: :float },
          { name: "ok", kind: :scalar, type: :boolean },
          { name: "bad", kind: :scalar, type: :integer },
        ])
    end

    it "executes int/float/bool during the walk" do
      result = descriptor.materialize(xml)
      n = result.at(0); p = result.at(1); ok = result.at(2); bad = result.at(3)
      expect(n.int_value).to eq(42)
      expect(p.float_value).to eq(2.5)
      expect(ok.bool_value).to be(true)
      # soft-fail: non-numeric source → nil from the accessor
      expect(bad.int_value).to be_nil
      # and the lenient Ruby path in to_ruby still answers the raw string
      expect(bad.to_ruby).to eq("zzz")
    end

    it "keeps string_value populated for backward compatibility" do
      result = descriptor.materialize(xml)
      expect(result.at(0).string_value).to eq("42")
    end
  end

  # #1269b: fused parse→walk→free
  describe "materialize fusion" do
    it "stays byte-parity with parse + walk(root)" do
      xml = %(<r><x k="1">v</x><y>2</y></r>)
      descriptor = Leptris::XML::Descriptor.build(
        name: "r", children: [
          { name: "x", kind: :nested, plan: {
              name: "x", attributes: [{ name: "k", kind: :scalar, type: :integer }],
              children: [] } },
          { name: "y", kind: :scalar, type: :integer },
        ])
      doc = Leptris::XML::Document.parse(xml)
      fused = descriptor.materialize(xml).to_ruby
      walked = descriptor.walk(doc.root).to_ruby
      doc.free
      expect(fused).to eq(walked)
    end
  end

  # #298.1: the crossings floor collapses with the fusion + in-pass types
  describe "the 5k-row ISO crossings floor (post-fusion)" do
    let(:iso) do
      rows = (0...5000).map do |i|
        %(<row id="#{i}" ts="t"><name>Item #{i}</name><price>#{i}.99</price><active>true</active></row>)
      end
      %(<?xml version="1.0"?><iso>) + rows.join + %(</iso>)
    end

    let(:iso_descriptor) do
      Leptris::XML::Descriptor.build(
        name: "iso",
        children: [{ name: "row", kind: :collection, plan: {
          name: "row",
          attributes: [{ name: "id", kind: :scalar, type: :integer }],
          children: [{ name: "name", kind: :scalar }] } }])
    end

    it "drops below the pre-fusion ~5/row floor" do
      result = iso_descriptor.materialize(iso)
      result.reset_crossings!
      result.as_kwarg_hash
      per_row = result.crossings / 5000.0
      expect(per_row).to be < 5.0
    end
  end
end
