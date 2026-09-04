# frozen_string_literal: true

RSpec.describe "Leptris::XML::XQuery (libleptris 1.9.64-1.9.66)" do
  let(:doc) do
    Leptris::XML::Document.parse(<<~XML)
      <catalog>
        <item qty="5"><name>Alpha</name></item>
        <item qty="2"><name>Beta</name></item>
        <item qty="9"><name>Gamma</name></item>
      </catalog>
    XML
  end

  def xquery(query)
    Leptris::XML::XQuery.parse(query).eval(doc)
  end

  it "compiles once and evaluates many times" do
    query = Leptris::XML::XQuery.parse("count(//item)")
    expect(query.eval(doc)).to eq(3.0)
    expect(query.eval(Leptris::XML::Document.parse("<r><item/><item/></r>"))).to eq(2.0)
  end

  it "runs FLWOR with where and stable order by" do
    expect(xquery("for $i in //item where number($i/@qty) > 3 order by $i/@qty descending return $i").size).to eq(2)
  end

  it "aggregates a plain for-return through count" do
    expect(xquery("count(for $i in //item return $i)")).to eq(3.0)
  end

  it "binds declare variable in the prolog" do
    expect(xquery(%q{declare variable $min := 3; count(//item[@qty > $min])})).to eq(2.0)
  end

  it "declares and calls local functions" do
    expect(xquery("declare function local:double($x) { $x * 2 }; local:double(21)")).to eq(42.0)
  end

  it "builds direct constructors with attribute value templates" do
    expect(xquery(%q{<out total="{count(//item)}">{string(//item[1]/name)}</out>}))
      .to eq('<out total="3">Alpha</out>')
  end

  it "builds computed constructors" do
    expect(xquery(%q{element big { string(//item[3]/name) }})).to eq("<big>Gamma</big>")
  end

  it "partitions the tuple stream with group by (1.9.67)" do
    grouped = Leptris::XML::Document.parse(
      "<r><i cat=\"a\"/><i cat=\"b\"/><i cat=\"a\"/><i cat=\"b\"/><i cat=\"a\"/></r>")
    result = Leptris::XML::XQuery.parse(
      "for $i in //i group by $c := $i/@cat return $i")
    # two groups (a: 3 members, b: 2); the items ride the sequence
    # channel — one item per group, sizes readable
    expect(result.eval(grouped).size).to eq(2)
  end

  it "binds the positional variable in for-at" do
    expect(xquery("for $i at $p in //item return $i").size).to eq(3)
  end

  it "aggregates a where/at FLWOR through a function argument (leptris/leptris#790 follow-up fixed in 1.9.76)" do
    expect(xquery("count(for $i in //item where number($i/@qty) > 3 return $i)")).to eq(2.0)
  end

  it "evaluates plain XPath expressions with their result types" do
    expect(xquery("count(//item)")).to eq(3.0)
    expect(xquery("//item/name")).to be_a(Leptris::XML::NodeSet)
  end

  it "evaluates against an element context node" do
    item = doc.at_css("item")
    expect(Leptris::XML::XQuery.parse("string(name)").eval(item)).to eq("Alpha")
    expect(Leptris::XML::XQuery.parse("name").eval(item))
      .to be_a(Leptris::XML::NodeSet)
  end

  it "raises XPathError on a syntax error" do
    expect { xquery("for $x in !!!") }
      .to raise_error(Leptris::XML::XPathError, /parse failed/)
  end

  it "returns a constructor from a for clause (leptris/leptris#790 fixed in 1.9.68)" do
    # constructor items arrive as readable serialized strings
    result = xquery(%q{for $i in //item return <v>{$i/name/text()}</v>})
    expect(result.map(&:content).join)
      .to eq("<v>Alpha</v><v>Beta</v><v>Gamma</v>")
  end
end

RSpec.describe "XPath 3.1 value-level surface (libleptris 1.9.51-1.9.63)" do
  let(:doc) { Leptris::XML::Document.parse("<r/>") }

  {
    "map lookup ?key"            => ["map { 'b': 'beta' }?b", "beta"],
    "map:get"                    => ["map:get(map { 'b': 'beta' }, 'b')", "beta"],
    "map:size"                   => ["map:size(map { 'a': 1, 'b': 2 })", 2.0],
    "array lookup ?index"        => ["[10, 20, 30]?2", "20"],
    "array:get"                  => ["array:get([10, 20, 30], 2)", "20"],
    "array:size"                 => ["array:size([10, 20, 30])", 3.0],
    "parse-json + lookup"        => [%(parse-json('{"b": "beta", "n": 2}')?b), "beta"],
    "serialize json method"      => [
      %(serialize(parse-json('{"b": "beta", "n": 2}'), map { 'method': 'json' })),
      '{"b":"beta","n":2}'],
    "closure immediate call"     => ["function($x) { $x + 1 }(41)", 42.0],
    "let-bound closure call"     => ["let $f := function($x) { $x * 2 } return $f(21)", 42.0],
    "function-lookup item"       => ["function-lookup('concat', 2) instance of item()", true],
    "fold-left"                  => ["fold-left(1 to 4, 0, function($a, $b) { $a + $b })", "10"],
  }.each do |label, (expr, expected)|
    it "evaluates #{label}" do
      expect(doc.xpath(expr)).to eq(expected)
    end
  end

  it "counts for-each sequence items" do
    expect(doc.xpath("count(for-each(1 to 3, function($x) { $x * 10 }))")).to eq(3.0)
  end
end

RSpec.describe "Leptris::XML.buffer_has_nonstandard_entity? (libleptris 1.9.62, #745)" do
  {
    %q{<r>a &amp; b &#65; &#x41;</r>} => false,
    %q{<r>&nbsp;</r>}                 => true,
    %q{<r>&mdash; &amp;</r>}          => true,
    %q{<r>a & b</r>}                  => false, # bare & — the parser's business
    %q{<r/>}                          => false,
  }.each do |xml, expected|
    it "answers #{expected} for #{xml}" do
      expect(Leptris::XML.buffer_has_nonstandard_entity?(xml)).to be(expected)
    end
  end
end

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

RSpec.describe "sequence items are readable (ResultText)" do
  let(:doc) { Leptris::XML::Document.parse(%q{<r><a v="1"/><a v="2"/></r>}) }

  it "serves for-return string values through #content" do
    expect(doc.xpath("for $w in //a return string($w/@v)").map(&:content))
      .to eq(["1", "2"])
  end

  it "serves sequence literals item by item" do
    expect(doc.xpath("(1, 2, 3)").map(&:content)).to eq(%w[1 2 3])
    expect(doc.xpath("(4, 5)")[1].content).to eq("5")
  end

  it "composes through inner_text" do
    expect(doc.xpath("(4, 5)").inner_text).to eq("45")
  end

  it "keeps map values readable through the aggregate path" do
    expect(doc.xpath("string-join((1 to 3), ',')")).to eq("1,2,3")
  end
end

RSpec.describe "XPath 2.0 ledger standalone (libleptris 1.9.69-1.9.73)" do
  let(:doc) { Leptris::XML::Document.parse(%q{<r><a v="1"/><a v="2"/></r>}) }

  {
    "value comparator eq"  => ["//a[1]/@v eq '1'", true],
    "value comparator gt"  => ["2 gt 1", true],
    "quantifier some"      => ["some $a in //a satisfies number($a/@v) > 1", true],
    "quantifier every"     => ["every $a in //a satisfies number($a/@v) >= 1", true],
    "except"               => ["count(//a except //a[@v = 1])", 1.0],
    "intersect"            => ["count(//a intersect //a[@v = 1])", 1.0],
    "node identity is"     => ["string(//a[1] is //a[1])", "true"],
  }.each do |label, (expr, expected)|
    it "evaluates #{label}" do
      expect(doc.xpath(expr)).to eq(expected)
    end
  end
end

RSpec.describe "XQuery windows and typeswitch (libleptris 1.9.69-1.9.70)" do
  let(:doc) { Leptris::XML::Document.parse(%q{<r><i/><i/><i/></r>}) }

  it "enumerates tumbling windows" do
    expect(Leptris::XML::XQuery.parse(
      "for tumbling window $w in //i start when true() end when true() return count($w)"
    ).eval(doc).map(&:content)).to eq(%w[2 1])
  end

  it "dispatches typeswitch cases" do
    expect(Leptris::XML::XQuery.parse(
      "typeswitch (//i[1]) case element() return 'el' default return 'other'"
    ).eval(doc)).to eq("el")
  end
end
