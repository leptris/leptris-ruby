# frozen_string_literal: true

require "spec_helper"

# Single-crossing element construction (libleptris 1.9.237, #1344):
# create_element with an attributes hash builds element + attributes
# in ONE engine crossing, with per-pair set_attribute semantics
# (duplicate names replace last-wins; nil values store the empty
# string). The native face falls back to create + per-pair sets on
# pins predating #1344.
RSpec.describe "Document#create_element with attributes" do
  let(:doc) { Leptris::XML.parse("<r/>") }

  it "applies every attribute in the construction crossing" do
    e = doc.create_element("book", "id" => "1", "lang" => "en")
    expect(e.name).to eq("book")
    expect(e["id"]).to eq("1")
    expect(e["lang"]).to eq("en")
    expect(e.keys.sort).to eq(%w[id lang])
  end

  it "stores nil values as the empty string" do
    e = doc.create_element("b", "x" => nil, "y" => "")
    expect(e["x"]).to eq("")
    expect(e["y"]).to eq("")
  end

  it "coerces non-string keys and values" do
    e = doc.create_element("b", 1 => "a", "n" => 42, :sym => :v)
    expect(e["1"]).to eq("a")
    expect(e["n"]).to eq("42")
    expect(e["sym"]).to eq("v")
  end

  it "matches the per-pair create+set result byte-for-byte" do
    hash = { "id" => "7", "kind" => "x", "note" => nil }
    via_hash = doc.create_element("e", hash)
    via_pairs = doc.create_element("e2").tap do |n|
      hash.each { |k, v| n[k] = v }
    end
    expect(via_hash.to_xml).to eq(via_pairs.to_xml.sub("e2", "e"))
  end

  it "attaches and serializes like any constructed element" do
    e = doc.create_element("book", "id" => "9")
    e << doc.create_element("title")
    doc.root << e
    expect(doc.root.to_xml).to include(%(<book id="9"><title/></book>))
  end

  it "keeps the no-attributes arity and the empty-hash shape" do
    expect(doc.create_element("x").name).to eq("x")
    expect(doc.create_element("y", {}).keys).to eq([])
  end

  it "rejects non-Hash attribute containers" do
    expect { doc.create_element("x", [%w[a b]]) }.to raise_error(TypeError)
  end

  it "resolves through the FFI seam face directly" do
    skip "native layer loaded — the Ruby path rides the ext" if
      defined?(Leptris::XML::NATIVE_FAST)
    names = %w[id lang]
    values = %w[3 fr]
    nb, na = Leptris::XML::CStringArray.to_c(names)
    vb, va = Leptris::XML::CStringArray.to_c(values)
    ptr = Leptris::XML::FFI.leptris_element_new_with_attributes(
      doc.c_ptr, "e", nb, vb, names.size)
    e = Leptris::XML::Node.wrap_fresh(
      ptr, doc, Leptris::XML::FFI::NODE_ELEMENT)
    expect(e["id"]).to eq("3")
    expect(e["lang"]).to eq("fr")
  end
end
