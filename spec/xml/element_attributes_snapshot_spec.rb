# frozen_string_literal: true

require "spec_helper"

# libleptris 1.9.353 (leptris#1689): ALL attribute names/values in
# ONE FFI crossing — the element sibling of PlanValue#attributes_
# snapshot (#447). Two-phase capacity/retry; ns lanes stay NULL on
# the Ruby surface and prefixed attributes ride the names lane
# spelled as the element spells them.
RSpec.describe "Element#attributes_snapshot" do
  it "returns all attributes as a plain hash in document order" do
    doc = Leptris::XML.parse('<r a="1" b="2" c="3"/>')
    expect(doc.root.attributes_snapshot)
      .to eq("a" => "1", "b" => "2", "c" => "3")
  end

  it "returns a frozen empty hash when nothing is bound" do
    doc = Leptris::XML.parse("<r/>")
    snap = doc.root.attributes_snapshot
    expect(snap).to eq({}).and(be_frozen)
  end

  it "matches the per-name reader on every entry" do
    doc = Leptris::XML.parse(
      '<e one="1" two="ii" three="3"/>'
    )
    e = doc.root
    snap = e.attributes_snapshot
    snap.each do |name, value|
      expect(e[name]).to eq(value)
    end
  end

  it "decodes entity references like the per-name reader" do
    doc = Leptris::XML.parse('<e v="a&amp;b &lt;c&gt;"/>')
    expect(doc.root.attributes_snapshot).to eq("v" => "a&b <c>")
  end

  it "returns UTF-8-encoded names and values" do
    doc = Leptris::XML.parse('<e prix="café" texte="naïve"/>')
    snap = doc.root.attributes_snapshot
    expect(snap).to eq("prix" => "café", "texte" => "naïve")
    snap.each do |name, value|
      expect(name.encoding).to eq(Encoding::UTF_8)
      expect(value.encoding).to eq(Encoding::UTF_8)
    end
  end

  it "carries prefixed attributes by their spelled name" do
    doc = Leptris::XML.parse(
      '<e xmlns:x="urn:x" x:k="v1" plain="v2"/>'
    )
    expect(doc.root.attributes_snapshot)
      .to eq("x:k" => "v1", "plain" => "v2")
  end

  it "handles values larger than any initial guess" do
    long = "x" * 4096
    doc = Leptris::XML.parse(%(<e a="#{long}" b="tail"/>))
    expect(doc.root.attributes_snapshot)
      .to eq("a" => long, "b" => "tail")
  end

  it "is stable across repeated calls on the same element" do
    doc = Leptris::XML.parse('<r k="v"/>')
    e = doc.root
    first = e.attributes_snapshot
    expect(e.attributes_snapshot).to eq(first)
  end
end
