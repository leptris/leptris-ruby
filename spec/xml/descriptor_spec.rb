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

# libleptris 1.9.312 (#1551): plan-guided serialization. The plan
# supplies element wrappers (row wire_name + ns_prefix), the walk
# result the content; children emit in document order and every
# distinct (prefix, uri) pair is declared exactly once, on the
# output root, in first-encounter order.
RSpec.describe "Descriptor#serialize (1.9.312, #1551)" do
  it "round-trips a namespaced subtree with prefixed wire names" do
    plan = Leptris::XML::Descriptor.build(
      name: "doc", ns: { exact: "urn:w" }, ns_prefix: "w",
      children: [
        { name: "body", kind: :nested, ns: { exact: "urn:w" },
          ns_prefix: "w", plan: {
            name: "body", ns: { exact: "urn:w" },
            attributes: [{ name: "id", kind: :scalar,
                           ns: { exact: "urn:w" }, ns_prefix: "w" }],
            children: [
              { name: "p", kind: :scalar,
                ns: { exact: "urn:w" }, ns_prefix: "w" },
            ] } },
      ])
    doc = Leptris::XML::Document.parse(
      %(<w:doc xmlns:w="urn:w"><w:body w:id="7"><w:p>text</w:p></w:body></w:doc>))
    expect(plan.serialize(plan.walk(doc.root)))
      .to eq(%(<w:doc xmlns:w="urn:w"><w:body w:id="7"><w:p>text</w:p></w:body></w:doc>))
  end

  it "declares each distinct prefix once on the root, first-encounter order" do
    plan = Leptris::XML::Descriptor.build(
      name: "d", ns: { exact: "urn:a" }, ns_prefix: "a",
      children: [
        { name: "b", kind: :scalar, ns: { exact: "urn:b" }, ns_prefix: "b" },
        { name: "c", kind: :scalar, ns: { exact: "urn:a" }, ns_prefix: "a" },
      ])
    doc = Leptris::XML::Document.parse(
      %(<a:d xmlns:a="urn:a" xmlns:b="urn:b"><b:b>B</b:b><a:c>C</a:c></a:d>))
    expect(plan.serialize(plan.walk(doc.root)))
      .to eq(%(<a:d xmlns:a="urn:a" xmlns:b="urn:b"><b:b>B</b:b><a:c>C</a:c></a:d>))
  end

  it "escapes text and keeps plans without ns_prefix bare" do
    plan = Leptris::XML::Descriptor.build(
      name: "r", children: [{ name: "t", kind: :scalar }])
    doc = Leptris::XML::Document.parse(%(<r><t>a &amp; b &lt;tag&gt;</t></r>))
    expect(plan.serialize(plan.walk(doc.root)))
      .to eq(%(<r><t>a &amp; b &lt;tag&gt;</t></r>))
  end
end

# libleptris 1.9.312 (#1552): WILDCARD rows — the remainder bucket.
# Named sibling rows take precedence regardless of row order; the
# row emits exactly one COLLECTION (even when empty); an explicit
# ns: filters the remainder.
RSpec.describe "wildcard child rows (1.9.312, #1552)" do
  it "binds the remainder in document order, named rows win" do
    plan = Leptris::XML::Descriptor.build(
      name: "r",
      children: [
        { name: "rest", kind: :wildcard },
        { name: "known", kind: :scalar },
      ])
    doc = Leptris::XML::Document.parse(
      "<r><known>a</known><other>1</other><extra>2</extra></r>")
    tree = plan.walk(doc.root).to_ruby
    expect(tree[:children]).to eq(["a", ["<other>1</other>", "<extra>2</extra>"]])
  end

  it "echoes an empty collection when every child was named" do
    plan = Leptris::XML::Descriptor.build(
      name: "r",
      children: [
        { name: "known", kind: :scalar },
        { name: "rest", kind: :wildcard },
      ])
    doc = Leptris::XML::Document.parse("<r><known>a</known></r>")
    expect(plan.walk(doc.root).to_ruby[:children]).to eq(["a", []])
  end

  it "ns: :none filters the remainder to no-namespace children" do
    plan = Leptris::XML::Descriptor.build(
      name: "r",
      children: [{ name: "rest", kind: :wildcard, ns: :none }])
    doc = Leptris::XML::Document.parse(
      %(<r xmlns:x="urn:x"><x:a/><b/></r>))
    expect(plan.walk(doc.root).to_ruby[:children]).to eq([["<b/>"]])
  end
end

# libleptris 1.9.317 (#1560): the UNQUALIFIED ns form matches the
# UNWRITTEN spelling on element rows — no written prefix,
# regardless of the effective namespace URI. Element-row only
# (attributes have no unprefixed namespace by XML rules).
RSpec.describe "unqualified child-row ns form (1.9.317, #1560)" do
  let(:plan) do
    Leptris::XML::Descriptor.build(
      name: "r",
      children: [
        { name: "c", kind: :nested, ns: :unqualified, plan: {
          name: "c", ns: :unqualified,
          attributes: [{ name: "x", kind: :scalar }],
          children: [{ name: "t", kind: :scalar, ns: :unqualified }] } },
      ])
  end

  it "binds unprefixed children under a namespace-less document" do
    doc = Leptris::XML::Document.parse(%(<r><c x="1"><t>v</t></c></r>))
    tree = plan.walk(doc.root).to_ruby
    expect(tree[:children].first[:attributes]).to eq("x" => "1")
    expect(tree[:children].first[:children]).to eq(["v"])
  end

  it "binds unprefixed children under a default-xmlns document" do
    doc = Leptris::XML::Document.parse(
      %(<r xmlns="urn:d"><c x="2"><t>w</t></c></r>))
    tree = plan.walk(doc.root).to_ruby
    expect(tree[:children].first[:attributes]).to eq("x" => "2")
    expect(tree[:children].first[:children]).to eq(["w"])
  end

  it "never binds prefixed spellings (the NS_ANY superset)" do
    doc = Leptris::XML::Document.parse(
      %(<r xmlns:p="urn:p"><p:c x="3"/></r>))
    expect(plan.walk(doc.root).to_ruby[:children]).to eq([])
  end

  it "round-trips: serialized bare form re-binds after re-parse" do
    doc = Leptris::XML::Document.parse(
      %(<r xmlns="urn:d"><c x="2"><t>w</t></c></r>))
    out = plan.serialize(plan.walk(doc.root))
    expect(out).to eq(%(<r><c x="2"><t>w</t></c></r>))
    rewalked = plan.walk(Leptris::XML::Document.parse(out).root).to_ruby
    expect(rewalked[:children].first[:children]).to eq(["w"])
  end

  it "rejects :unqualified in the boundary error message" do
    expect { Leptris::XML::Descriptor.build(name: "r", ns: :bogus) }
      .to raise_error(ArgumentError, /:unqualified/)
  end
end

# libleptris 1.9.316 (#1565): a captured child's rows resolve
# against the CAPTURING row's child_plan_index plan — a child
# bound by a nested row serializes its own attribute and child
# rows (the w:font-in-w:fonts shape) instead of silently
# vanishing against the parent plan.
RSpec.describe "nested-capture serialization (1.9.316, #1565)" do
  it "emits the inner rows at every nesting level" do
    plan = Leptris::XML::Descriptor.build(
      name: "fonts", ns: { exact: "urn:w" }, ns_prefix: "w",
      children: [
        { name: "font", kind: :nested, ns: { exact: "urn:w" },
          ns_prefix: "w", plan: {
            name: "font", ns: { exact: "urn:w" },
            attributes: [{ name: "name", kind: :scalar }],
            children: [
              { name: "sz", kind: :scalar,
                ns: { exact: "urn:w" }, ns_prefix: "w" },
            ] } },
      ])
    doc = Leptris::XML::Document.parse(
      %(<w:fonts xmlns:w="urn:w"><w:font name="A"><w:sz>12</w:sz></w:font></w:fonts>))
    expect(plan.serialize(plan.walk(doc.root)))
      .to eq(%(<w:fonts xmlns:w="urn:w"><w:font name="A"><w:sz>12</w:sz></w:font></w:fonts>))
  end
end
