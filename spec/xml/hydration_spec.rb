# frozen_string_literal: true
require "leptris"
require "leptris/xml/native_layer"

# #230 (moxml/lutaml's "parse is 0.27% of total"): the binding's
# bulk hydration surface — one C walk per subtree, no per-node
# wrapper construction, no per-attribute Ruby round-trips.
RSpec.describe "bulk hydration surface (TODO.perf/38, #230)" do
  let(:doc) do
    Leptris::XML::Document.parse(
      %q{<r xmlns:w="urn:w"><e w:x="1" y="2"><c/>txt</e><f/></r>})
  end
  let(:root) { doc.root }

  it "snapshot returns one Hash per node in document order" do
    skip "n/a in NO_NATIVE" unless defined?(Leptris::XML::NATIVE_FAST)
    rows = doc.snapshot(root)
    expect(rows.map { |r| [r[:kind], r[:name]] })
      .to eq([["element", "r"], ["element", "e"], ["element", "c"],
              ["text", nil], ["element", "f"]])
  end

  it "exposes namespace, attrs as [name,value] pairs, and first text" do
    skip "n/a in NO_NATIVE" unless defined?(Leptris::XML::NATIVE_FAST)
    e = doc.snapshot(root).find { |r| r[:name] == "e" }
    expect(e[:prefix]).to be_nil
    expect(e[:uri]).to be_nil
    expect(e[:attrs]).to eq([["w:x", "1"], ["y", "2"]])
    expect(e[:text]).to eq("txt")
  end

  it "walk_subtree yields rows without constructing Node wrappers" do
    skip "n/a in NO_NATIVE" unless defined?(Leptris::XML::NATIVE_FAST)
    seen = []
    doc.walk_subtree(root) { |row| seen << row[:name] }
    expect(seen).to eq(["r", "e", "c", nil, "f"])
  end

  it "Document.open yields and frees on normal exit (#231)" do
    yielded = nil
    result = Leptris::XML::Document.open("<r/>") do |doc|
      yielded = doc
      doc.root.name
    end
    expect(result).to eq("r")
    expect(yielded.freed?).to be(true)
    expect { yielded.root }.to raise_error(Leptris::XML::UseAfterFreeError)
  end

  it "Document.open frees even on raise (#231)" do
    yielded = nil
    expect {
      Leptris::XML::Document.open("<r/>") do |doc|
        yielded = doc
        doc.root.name
        raise "boom"
      end
    }.to raise_error("boom")
    expect(yielded.freed?).to be(true)
  end
end
