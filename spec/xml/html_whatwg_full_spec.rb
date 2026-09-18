# frozen_string_literal: true

# The WHATWG HTML engine is feature-complete upstream (leptris/leptris
# #659 closed: full active-formatting-elements + adoption agency,
# RCDATA/rawtext family, script-data escaped states, in-table
# clear-stack + frameset drop, foreign integration points, after-body
# restore, template, bogus-markup edges). This battery pins the
# shipped behavior classes in the binding — the "bindings expose
# html" tail of #659.

RSpec.describe "WHATWG HTML full compatibility (libleptris #659 closed)" do
  def whatwg(html)
    Leptris::XML.parse_html(html, mode: :whatwg)
  end

  it "reconstructs active formatting elements across paragraphs" do
    doc = whatwg("<p><b>bold<p>carries")
    bs = doc.css("b")
    expect(bs.size).to eq(2)
    # the second <b> is reconstructed inside the new <p>
    expect(bs[1].parent.name).to eq("p")
    expect(doc.css("p").size).to eq(2)
  end

  it "applies the adoption agency on misnested formatting" do
    doc = whatwg("<b><p>x</b>y</p>")
    # spec: <b> closes before <p>, then REOPENS inside it —
    # <b></b><p><b>x</b>y</p>
    expect(doc.css("b").size).to eq(2)
    expect(doc.css("p").size).to eq(1)
    expect(doc.at_css("p").content).to eq("xy")
    inner_b = doc.at_css("p b")
    expect(inner_b).not_to be_nil
  end

  it "caps identical formatting elements at three (Noah's Ark)" do
    doc = whatwg("<b><b><b><p>x</b></p>")
    # 3 in the open list (cap) + the reopened one inside <p>
    expect(doc.css("b").size).to eq(4)
    expect(doc.at_css("p b")).not_to be_nil
  end

  it "keeps template content out of the live table machinery" do
    doc = whatwg("<template><tr><td>c</td></tr></template>")
    t = doc.at_css("template")
    expect(t).not_to be_nil
    # in-template table content does NOT synthesize table/tbody
    expect(doc.css("table")).to be_empty
    expect(doc.css("tbody")).to be_empty
  end

  it "parses RCDATA (title/textarea) as text" do
    doc = whatwg("<title><b>not an element</b></title>")
    expect(doc.at_css("title").children.select(&:element?)).to be_empty
    expect(doc.at_css("title").content).to include("<b>not an element</b>")

    doc = whatwg("<textarea>&<div>raw</div></textarea>")
    expect(doc.at_css("textarea").children.select(&:element?)).to be_empty
  end

  it "keeps rawtext (iframe/noembed/xmp/style) element-free" do
    doc = whatwg("<xmp><i>x</i></xmp><style>p {}</style>")
    expect(doc.at_css("xmp").children.select(&:element?)).to be_empty
    expect(doc.at_css("style").children.select(&:element?)).to be_empty
  end

  it "foster-parents in-table stray text before the table" do
    doc = whatwg("<table><tr><td>c</td></tr>stray</table>")
    # the stray text lands OUTSIDE the table, before it (foster
    # parenting), not inside the table element
    body_kids = doc.at_css("body").children
    stray = body_kids.select(&:text?).map(&:content).join
    expect(stray).to include("stray")
    expect(doc.at_css("table").content).not_to include("stray")
  end

  it "drops frameset-mode content" do
    doc = whatwg("<frameset><frame><div>dropped</div></frameset><p>after</p>")
    expect(doc.css("div").size).to eq(0)
    expect(doc.css("frameset").size).to eq(1)
  end

  it "treats foreign content (svg/math) with adjusted casing" do
    doc = whatwg(%q{<svg><foreignObject><p>x</p></foreignObject></svg>})
    fo = doc.at_xpath("//*[local-name()='foreignObject']")
    expect(fo).not_to be_nil
    expect(fo.namespace.href).to eq("http://www.w3.org/2000/svg")
  end

  it "restores after-body on non-whitespace text (#659 v1.9.187)" do
    doc = whatwg("<html><body><p>x</p></body>tail<!--c--></html>")
    body = doc.at_css("body")
    expect(body.content).to include("tail")
    expect(body.children.last.comment?).to be true
  end

  it "escapes through script-data states" do
    doc = whatwg("<script>var s = '<!--<script>x</script>-->';</script><p>live</p>")
    expect(doc.css("script").size).to eq(1)
    expect(doc.css("p").size).to eq(1)
    expect(doc.at_css("p").content).to eq("live")
  end

  it "synthesizes the full implied-head set for bare content" do
    doc = whatwg("<script>var x</script><p>t</p>")
    expect(doc.at_css("head script")).not_to be_nil
    expect(doc.at_css("body p")).not_to be_nil
  end
end
