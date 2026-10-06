# frozen_string: true

require "spec_helper"

# #374 lever 2: markup-accumulating construction. The block turns
# into well-formed markup in Ruby; the flush performs ONE native
# crossing for the whole subtree (parse + root= adoption for
# document sinks, append_markup for element sinks).
RSpec.describe Leptris::XML::Builder do
  it "builds a document with one root through Document#build" do
    doc = Leptris::XML::Document.create
    root = doc.build do |b|
      b.catalog(id: "c") do
        b.item(id: 7) { b.name "Item 7" }
      end
    end
    expect(root).to be_a(Leptris::XML::Element)
    expect(root.name).to eq("catalog")
    expect(root["id"]).to eq("c")
    item = root.element_children.first
    expect(item.name).to eq("item")
    expect(item["id"]).to eq("7")
    expect(item.at_xpath("name").content).to eq("Item 7")
    expect(doc.root).to equal(root)
  end

  it "covers the node shapes: empty, text, attrs, cdata, comment, raw" do
    doc = Leptris::XML::Document.create
    doc.build do |b|
      b.r do
        b.a
        b.b("solo text")
        b.c(x: "1")
        b.cdata("<x>&</x>")
        b.comment "hi"
        b.raw("<z>verbatim</z>")
      end
    end
    expect(doc.root.to_xml).to eq(
      %(<r><a/><b>solo text</b><c x="1"/>) +
      %(<![CDATA[<x>&</x>]]><!--hi--><z>verbatim</z></r>))
  end

  it "escapes text and attribute values in one pass" do
    doc = Leptris::XML::Document.create
    doc.build do |b|
      b.r { b.t('a & b < "c"'); b.u(x: 'q"uote&<') }
    end
    expect(doc.root.to_xml).to eq(
      %(<r><t>a &amp; b &lt; "c"</t><u x="q&quot;uote&amp;&lt;"/></r>))
  end

  it "matches the object face byte-for-byte on the same tree" do
    built = Leptris::XML::Document.create
    built.build do |b|
      b.r { b.c(x: "1"); b.d(x: "1") { b.e } }
    end
    made = Leptris::XML::Document.create
    r = made.create_element("r"); made.root = r
    c = made.create_element("c"); c["x"] = "1"; r.add_child(c)
    d = made.create_element("d"); d["x"] = "1"; r.add_child(d)
    d.add_child(made.create_element("e"))
    expect(built.root.to_xml).to eq(made.root.to_xml)
  end

  it "rejects multiple roots (the parser enforces the contract)" do
    doc = Leptris::XML::Document.create
    expect do
      doc.build { |b| b.one { b.two }; b.three }
    end.to raise_error(Leptris::XML::ParseError)
  end

  it "rejects invalid explicit element names and weird method tails" do
    doc = Leptris::XML::Document.create
    expect do
      doc.build { |b| b.element("bad<name>") }
    end.to raise_error(ArgumentError, /element name must match/)
    builder = described_class.new(doc)
    expect { builder.nope? }.to raise_error(NoMethodError)
  end

  it "appends children through Element#build returning the added set" do
    doc = Leptris::XML::Document.create
    doc.build { |b| b.r { b.keep "k" } }
    item = doc.root
    added = item.build do |b|
      b.note "added"
      b.meta(k: "1")
    end
    expect(added).to be_a(Leptris::XML::NodeSet)
    expect(added.map(&:name)).to eq(%w[note meta])
    expect(item.to_xml).to eq(
      %(<r><keep>k</keep><note>added</note><meta k="1"/></r>))
  end

  it "flush returns the same wrapper #root yields (identity)" do
    doc = Leptris::XML::Document.create
    root = doc.build { |b| b.r { b.x } }
    expect(doc.root).to equal(root)
    expect(doc.root.c_ptr.address).to eq(root.c_ptr.address)
  end
end
