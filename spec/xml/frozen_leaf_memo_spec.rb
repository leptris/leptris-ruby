# frozen_string_literal: true

require "spec_helper"

# Frozen-tree leaf-content memo (leptris-ruby#336): frozen leaves are
# COW — never written in place — so a populated content memo is
# eternally valid and the version-checked memo chain (memo_hit? +
# ensure_alive! + Document#version) is skipped on repeat reads.
# Elements are excluded: a frozen parent's child slot is re-pointed
# on child COW, so subtree content can change.
RSpec.describe "frozen-tree leaf content memo" do
  let(:doc) { Leptris::XML.parse("<r><t>hello</t><c><![CDATA[cd]]></c><!--cm--><e>x</e></r>") }

  def elem(tag)
    doc.root.children.find { |n| n.name == tag }
  end

  def leaf_of(tag)
    elem(tag).children.first
  end

  it "memoizes frozen text content and repeats it stably" do
    t = leaf_of("t")
    first = t.content
    3.times { expect(t.content).to eq(first) }
    expect(first).to eq("hello")
    expect(doc.frozen_tree?).to be(true)
  end

  it "memoizes comment and CDATA content under the frozen tree" do
    comment = doc.root.children.find { |n| n.is_a?(Leptris::XML::Comment) }
    cdata = leaf_of("c")
    expect(comment.content).to eq("cm")
    expect(comment.content).to eq("cm")
    expect(cdata.content).to eq("cd")
    expect(cdata.content).to eq("cd")
  end

  it "keeps the version-checked path for writable documents" do
    doc2 = Leptris::XML::Document.create
    root = doc2.create_element("r")
    doc2.root = root
    t = doc2.create_text_node("one")
    root.add_child(t)
    expect(doc2.frozen_tree?).to be(false)
    expect(t.content).to eq("one")
    t.content = "two"
    expect(t.content).to eq("two")
  end

  it "sees frozen-leaf reads consistent after a sibling mutation" do
    t = leaf_of("t")
    before = t.content
    elem("e").content = "mutated" # COW copy; frozen t untouched
    expect(t.content).to eq(before)
    expect(elem("e").content).to eq("mutated")
  end
end
