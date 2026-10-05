# frozen_string_literal: true

require "spec_helper"

# 1.9.304 / #1528: foreign nodes are ADOPTED BY COPY at the splice.
# The binding must return the INSTALLED wrapper — the original
# points at the detached source, which dies with its document
# (the xpath.rb:39 compiled-eval crash shape: scratch-doc markup
# appended into a live tree, scratch freed, next eval detonated).
RSpec.describe "cross-document adoption (#1528)" do
  it "add_child of a foreign node returns the installed copy" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<new attr="v">t</new>))
    foreign = scratch.root
    installed = doc.root.add_child(foreign)
    expect(installed.name).to eq("new")
    expect(installed["attr"]).to eq("v")
    expect(installed.content).to eq("t")
    expect(doc.root.element_children.first).to equal(installed)
    expect(foreign.document).to equal(scratch) # source untouched
  end

  it "the installed copy survives scratch-document free + eval" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(
      %(<new><cite key="k">A</cite></new>))
    installed = doc.root.add_child(scratch.root)
    scratch.free # the #1528 detonator
    expect(doc.xpath("//cite/@key").map(&:value)).to eq(%w[k])
    expect(installed.name).to eq("new")
    expect(doc.root.to_xml).to eq(%(<r><new><cite key="k">A</cite></new></r>))
  end

  it "append_children re-wraps installed copies for foreign batches" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<s><a>1</a><b>2</b></s>))
    kids = scratch.root.element_children.to_a
    installed = doc.root.append_children(kids)
    expect(installed.map(&:name)).to eq(%w[a b])
    scratch.free
    expect(doc.xpath("//a").first.content).to eq("1")
    expect(doc.xpath("//b").first.content).to eq("2")
  end

  it "children= replaces wholesale with foreign lists" do
    doc = Leptris::XML::Document.parse(%(<r><old/></r>))
    scratch = Leptris::XML::Document.parse(%(<s><n1/><n2/></s>))
    doc.root.children = scratch.root.element_children.to_a
    scratch.free
    expect(doc.xpath("//n1")).not_to be_empty
    expect(doc.xpath("//n2")).not_to be_empty
  end

  it "same-document appends stay pointer-identical" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    kid = doc.create_element("same")
    ret = doc.root.add_child(kid)
    expect(ret).to equal(kid)
    batch = [doc.create_element("b1"), doc.create_element("b2")]
    expect(doc.root.append_children(batch)).to equal(batch)
  end
end
