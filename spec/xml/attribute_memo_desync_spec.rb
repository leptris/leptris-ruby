# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#526: attribute_nodes desyncs (answers nil — surfacing
# as [] through the `attribute_nodes || []` consumer idiom) after
# interleaved elem[...] accessor reads across elements. The cold
# bare-name [] read drops the sibling attribute memos
# (@attribute_nodes, @keys, @values) but restamps only
# @attributes_version; within one document version (no mutation)
# the dropped faces then memo-hit against nil and serve it.
RSpec.describe Leptris::XML::Element do
  let(:xml) do
    '<svg xmlns:xlink="urn:x"><use xlink:href="#grad" href="#grad" id="u"/></svg>'
  end
  let(:doc) { Leptris::XML::Document.parse(xml) }
  let(:use) { doc.root.children.first }

  # The reported shape: attribute_nodes materialized on a traversal
  # wrapper, then accessor reads (the svg_uniqueids port reads
  # e["id"] / e["clip-path"] on every element), then attribute_nodes
  # again — no mutation in between, one document version throughout.
  it "serves attribute_nodes across interleaved bare accessor reads" do
    expect(use.attribute_nodes.map(&:name)).to eq(%w[xlink:href href id])
    expect(use["id"]).to eq("u")
    expect(use["clip-path"]).to be_nil
    expect(use["id"]).to eq("u")
    expect(use.attribute_nodes.map(&:name)).to eq(%w[xlink:href href id])
  end

  it "serves attribute_nodes when the cold read comes first" do
    expect(use["clip-path"]).to be_nil
    expect(use.attribute_nodes.map(&:name)).to eq(%w[xlink:href href id])
    expect(use.attribute_nodes.map(&:name)).to eq(%w[xlink:href href id])
  end

  it "keeps keys and values serving across interleaved bare reads" do
    expect(use.keys).to eq(%w[xlink:href href id])
    expect(use.values).to eq(%w[#grad #grad u])
    expect(use["clip-path"]).to be_nil
    expect(use.keys).to eq(%w[xlink:href href id])
    expect(use.values).to eq(%w[#grad #grad u])
  end

  it "never serves a nil memo after any accessor interleaving" do
    faces = ->(e) { [e.attribute_nodes, e.keys, e.values] }
    before = faces.call(use)
    use["clip-path"]
    use["id"]
    use["xlink:href"]
    after = faces.call(use)
    expect(after).to all(be_an(Array))
    expect(after.map(&:class)).to eq(before.map(&:class))
  end

  # The consumer idiom from the issue (vectory SvgIdDisambiguator):
  # nodes = elem.attribute_nodes || [] — a nil memo made this [] and
  # silently skipped every rewrite for the element.
  it "answers the attribute_nodes || [] idiom with the real nodes" do
    expect(use.attribute_nodes.map(&:name)).to eq(%w[xlink:href href id])
    use["clip-path"]
    expect((use.attribute_nodes || []).map(&:name))
      .to eq(%w[xlink:href href id])
  end

  it "still invalidates the dropped faces on mutation" do
    expect(use.keys).to eq(%w[xlink:href href id])
    expect(use.attribute_nodes.map(&:name)).to eq(%w[xlink:href href id])
    use["id"] = "u_0"
    expect(use.keys).to eq(%w[xlink:href href id])
    expect(use["id"]).to eq("u_0")
    expect(use.attribute_nodes.map { |a| [a.name, a.value] })
      .to include(%w[id u_0])
  end
end

# Same memo machinery, found by the interleaving sweep while
# reproducing #526: the cold bare read caches queried-absent names
# as nil in the partial @attr_values; key? treated a partial-fill
# key as presence, so has_attribute?/remove_attribute lied after a
# bare [] read of a missing attribute.
RSpec.describe Leptris::XML::Element do
  let(:doc) { Leptris::XML::Document.parse('<a id="1"/>') }
  let(:a) { doc.root }

  it "does not let a cold [] read fake attribute presence" do
    expect(a.key?("clip-path")).to be(false)
    a["clip-path"]
    expect(a.key?("clip-path")).to be(false)
    expect(a.has_attribute?("clip-path")).to be(false)
  end

  it "still proves presence from the partial memo without a crossing" do
    a["id"]
    expect(a.key?("id")).to be(true)
  end

  it "lets remove_attribute answer truthfully after a cold [] read" do
    a["clip-path"]
    expect { a.remove_attribute("clip-path") }
      .to raise_error(Leptris::XML::Error)
  end
end
