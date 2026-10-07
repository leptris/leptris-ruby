# frozen_string_literal: true

require "spec_helper"

# #1559 cross-platform DOM contract for inter-element whitespace
# (engine PR #1569 test_whitespace_shape, mirrored here): the
# default parse PRESERVES whitespace-only text nodes, so "same
# input, same DOM" holds on every architecture leg. The 1.9.311
# linux-aarch64 prebuilt binary was the divergence source — these
# pins make any stale or diverging vendored binary go red on its
# own runner (ubuntu-24.04-arm exercises the published aarch64
# gem in gem-smoke).
RSpec.describe "whitespace DOM shape (#1559)" do
  it "keeps every indentation run between pretty-printed children" do
    doc = Leptris::XML::Document.parse("<r>\n  <a/>\n  <b/>\n</r>\n")
    shape = doc.root.children.map do |c|
      c.is_a?(Leptris::XML::Text) ? [:text, c.content] : [:element, c.name]
    end
    expect(shape).to eq([
      [:text, "\n  "], [:element, "a"],
      [:text, "\n  "], [:element, "b"],
      [:text, "\n"],
    ])
  end

  it "keeps the nested bibitem shape (relaton's field-presence signal)" do
    doc = Leptris::XML::Document.parse(
      %(<bibitem>\n  <title>\n    <span>Standard</span>\n  </title>\n  <extent/>\n</bibitem>\n))
    outer = doc.root.children.map do |c|
      c.is_a?(Leptris::XML::Text) ? [:text, c.content] : [:element, c.name]
    end
    expect(outer.first).to eq([:text, "\n  "])
    expect(outer.select { |e| e[0] == :element }.map(&:last)).to eq(%w[title extent])
    title = doc.root.element_children.first
    title_shape = title.children.map do |c|
      c.is_a?(Leptris::XML::Text) ? [:text, c.content] : [:element, c.name]
    end
    expect(title_shape.first).to eq([:text, "\n    "])
    expect(title_shape.last).to eq([:text, "\n  "])
    expect(title.at_xpath("span").content).to eq("Standard")
  end

  it "keeps sole-child whitespace as content" do
    doc = Leptris::XML::Document.parse("<r>\n  \n</r>")
    expect(doc.root.children.size).to eq(1)
    expect(doc.root.children.first).to be_a(Leptris::XML::Text)
    expect(doc.root.children.first.content).to eq("\n  \n")
  end

  it "normalizes CRLF runs to LF (XML 1.0 2.11)" do
    doc = Leptris::XML::Document.parse("<r>\r\n  <a/>\r\n</r>")
    shape = doc.root.children.map do |c|
      c.is_a?(Leptris::XML::Text) ? [:text, c.content] : [:element, c.name]
    end
    expect(shape).to eq([[:text, "\n  "], [:element, "a"], [:text, "\n"]])
  end

  it "keeps no text nodes in collapsed spellings" do
    doc = Leptris::XML::Document.parse("<r><a/><b/></r>")
    expect(doc.root.children.map(&:name)).to eq(%w[a b])
    expect(doc.root.children.grep(Leptris::XML::Text)).to be_empty
  end
end
