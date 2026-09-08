# frozen_string_literal: true

RSpec.describe "HTML parsing (libleptris 1.9.75, leptris/leptris#659)" do
  def children_xml(html)
    Leptris::XML.parse_html(html).at_css("body").inner_html
  end

  it "closes implied end tags" do
    expect(children_xml("<p>one<p>two")).to eq("<p>one</p><p>two</p>")
    expect(children_xml("<ul><li>a<li>b</ul>")).to eq("<ul><li>a</li><li>b</li></ul>")
  end

  it "keeps void elements self-closed with minimized attributes" do
    expect(children_html = children_xml("<img src=x><br>"))
      .to eq('<img src="x"/><br/>')
  end

  it "treats script and style as raw text" do
    expect(children_xml("<script>if (a < b) { x(); }</script>"))
      .to include("a &lt; b")
  end

  it "lowercases names and normalizes minimized attributes" do
    expect(children_xml(%(<DIV CLASS=Big>hi</DIV>))).to eq('<div class="Big">hi</div>')
  end

  it "synthesizes html/head/body but not tbody" do
    doc = Leptris::XML.parse_html("<table><tr><td>x</table>")
    expect(doc.at_css("html > body").name).to eq("body")
    expect(doc.at_css("table").inner_html).to eq("<tr><td>x</td></tr>")
  end

  it "resolves HTML named entities" do
    expect(children_xml("a &nbsp; &mdash; b")).to eq("a   — b")
  end

  it "degrades malformed markup to text instead of raising" do
    expect(children_xml("<b>bold</b")).to eq("<b>bold</b>")
  end
end

RSpec.describe "HTML PI-ish constructs (libleptris 1.9.83, leptris/leptris#659)" do
  it "keeps <?target data?> as a PI with the libxml2/Nokogiri shape" do
    body = Leptris::XML.parse_html("<?php echo 1 ?><p>t</p>").at_css("body")
    pi = body.children.first
    expect(pi).to be_a(Leptris::XML::ProcessingInstruction)
    expect(pi.name).to eq("php")
    expect(pi.content).to eq("echo 1 ?")
  end
end

RSpec.describe "HTML head-content placement lift (libleptris 1.9.84, leptris/leptris#659)" do
  def element_children_names(doc, sel)
    doc.at_css(sel).children.select(&:element?).map(&:name)
  end

  it "lifts a contiguous leading title/meta/link/base run into a synthesized head" do
    doc = Leptris::XML.parse_html("<title>T</title><meta charset='utf8'><p>x</p>")
    expect(element_children_names(doc, "html")).to eq(%w[head body])
    expect(element_children_names(doc, "head")).to eq(%w[title meta])
  end

  it "lifts link and base before body content" do
    doc = Leptris::XML.parse_html("<link rel='s'><base href='h'><div>d</div>")
    expect(element_children_names(doc, "head")).to eq(%w[link base])
  end

  it "does not lift once body content has started" do
    doc = Leptris::XML.parse_html("<p>x</p><title>T</title>")
    expect(doc.at_css("head")).to be_nil
    expect(element_children_names(doc, "body")).to eq(%w[p title])
  end

  it "never synthesizes an empty head" do
    doc = Leptris::XML.parse_html("<p>just body</p>")
    expect(doc.at_css("head")).to be_nil
  end
end

RSpec.describe "HTML characterization gates (libleptris 1.9.85, leptris/leptris#659)" do
  it "keeps template as an ordinary element with children in place" do
    tpl = Leptris::XML.parse_html("<template><p>inner</p></template>").at_css("template")
    expect(tpl.children.select(&:element?).map(&:name)).to eq(%w[p])
  end

  it "closes the formatting element at the outer end tag and drops the stray one" do
    body = Leptris::XML.parse_html("<b><i>x</b>y</i>").at_css("body")
    expect(body.inner_html).to eq("<b><i>x</i></b>y")
  end
end

RSpec.describe "HTML two-mode split (libleptris 1.9.104-1.9.105, leptris/leptris#659)" do
  it "defaults to the html4 entry — Nokogiri/libxml2 byte-parity holds" do
    body = Leptris::XML.parse_html("<script>var x</script><p>t</p>").at_css("body")
    expect(body.children.select(&:element?).map(&:name)).to eq(%w[script p])
  end

  it "lifts leading script into the implied head in whatwg mode" do
    doc = Leptris::XML.parse_html("<script>var x</script><p>t</p>", mode: :whatwg)
    expect(doc.at_css("head").children.select(&:element?).map(&:name)).to eq(%w[script])
  end

  it "foster-parents text before the table in whatwg mode" do
    kids = Leptris::XML.parse_html("<table><tr><td>c</td></tr>oops</table>", mode: :whatwg)
      .at_css("body").children
      .reject { |n| n.text? && n.content.strip.empty? }
      .map { |n| n.text? ? "text:#{n.content}" : n.name }
    expect(kids).to eq(["text:oops", "table"])
  end

  it "raises ArgumentError for an unknown mode" do
    expect { Leptris::XML.parse_html("<p/>", mode: :bogus) }
      .to raise_error(ArgumentError, /:html4 or :whatwg/)
  end
end

RSpec.describe "WHATWG adoption agency (libleptris 1.9.106-1.9.107, leptris/leptris#659)" do
  it "reopens formatting elements cloned at the new insertion point" do
    expect(Leptris::XML.parse_html("<b>1<i>2</b>3</i>", mode: :whatwg)
      .at_css("body").inner_html).to eq("<b>1<i>2</i></b><i>3</i>")
  end

  it "carries attributes onto the reopened clones" do
    expect(Leptris::XML.parse_html(%q{<a href="h">1<i>2</a>3</i>}, mode: :whatwg)
      .at_css("body").inner_html).to eq(%q{<a href="h">1<i>2</i></a><i>3</i>})
  end

  it "keeps the html4 entry on libxml2's pop-away shape" do
    expect(Leptris::XML.parse_html("<b>1<i>2</b>3</i>")
      .at_css("body").inner_html).to eq("<b>1<i>2</i></b>3")
  end
end
