# frozen_string_literal: true

require "spec_helper"

# Leptris::HTML.parse_fragment (#1634 / moxml#353): WHATWG
# fragment semantics composed over the WHATWG lane — the fragment
# runs inside the context element's chain, so head-only elements
# stay at fragment top level and table-structure tags take the
# in-body ignore rules. Byte-shaped against Nokogiri::HTML5.fragment
# on the canon divergence set.
RSpec.describe "Leptris::HTML.parse_fragment" do
  def self.engine_drops_table_struct?
    @engine_drops ||=
      Leptris::HTML.parse_fragment("<td>cell</td>")
        .children.map(&:name) == ["text"]
  end

  it "keeps head-swept elements at fragment top level" do
    frag = Leptris::HTML.parse_fragment("<title>T</title><p>x</p>")
    expect(frag.children.map(&:name)).to eq(%w[title p])
  end

  it "keeps meta/link at fragment top level" do
    frag = Leptris::HTML.parse_fragment(%(<meta charset="utf-8"><link rel="x">))
    expect(frag.children.map(&:name)).to eq(%w[meta link])
  end

  it "preserves whitespace-only text (no NOBLANKS semantics)" do
    frag = Leptris::HTML.parse_fragment("  <p>lead ws</p>  ")
    names = frag.children.map(&:name)
    expect(names.first).to eq("text")
    expect(names.last).to eq("text")
    expect(frag.children.first.content).to eq("  ")
  end

  it "is enumerable with size and empty?" do
    frag = Leptris::HTML.parse_fragment("<p>a</p><p>b</p>")
    expect(frag.size).to eq(2)
    expect(frag.map(&:name)).to eq(%w[p p])
    expect(frag).not_to be_empty
    expect(Leptris::HTML.parse_fragment("")).to be_empty
  end

  it "serializes as the children joined" do
    frag = Leptris::HTML.parse_fragment("<p>a</p>tail")
    expect(frag.to_html).to eq("<p>a</p>tail")
  end

  it "keeps the wrapper document alive for the fragment" do
    frag = Leptris::HTML.parse_fragment("<p>x</p>")
    GC.start
    expect(frag.children.first.name).to eq("p")
    expect(frag.to_html).to eq("<p>x</p>")
  end

  describe "table contexts" do
    it "parses inside the td chain" do
      frag = Leptris::HTML.parse_fragment("<b>x</b>", context: :td)
      expect(frag.children.map(&:name)).to eq(%w[b])
    end

    it "raises ArgumentError for an unknown context" do
      expect { Leptris::HTML.parse_fragment("<p/>", context: :nope) }
        .to raise_error(ArgumentError, /table context/)
    end
  end

  describe "foster-parenting divergence (Nokogiri::HTML5.fragment parity)" do
    before do
      unless self.class.engine_drops_table_struct?
        skip "vendored engine predates leptris#1638 (in-body table-structure drops)"
      end
    end

    it "drops bare td/tr/tbody elements, keeping their text" do
      expect(Leptris::HTML.parse_fragment("<td>cell</td>").children.map(&:name))
        .to eq(["text"])
      expect(Leptris::HTML.parse_fragment("<tr><td>a</td></tr>")
        .children.map(&:name)).to eq(["text"])
      expect(Leptris::HTML.parse_fragment("<tbody><tr><td>a</td></tr></tbody>")
        .children.map(&:name)).to eq(["text"])
    end

    it "keeps a real table with its implied tbody/tr" do
      frag = Leptris::HTML.parse_fragment("<table><td>x</table>")
      expect(frag.to_html)
        .to eq("<table><tbody><tr><td>x</td></tr></tbody></table>")
    end
  end
end
