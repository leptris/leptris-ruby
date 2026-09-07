# frozen_string_literal: true

require "leptris/xml"

RSpec.describe "Leptris::XML Searchable via XPath" do
  let(:doc) do
    Leptris::XML::Document.parse(<<~XML)
      <library version="2.0">
        <book id="1"><title>Ruby</title></book>
        <book id="2"><title>XML</title></book>
        <book id="3"><title>XPath</title></book>
      </library>
    XML
  end

  it "evaluates count() and returns a Float" do
    expect(doc.xpath("count(//book)")).to eq(3.0)
  end

  it "returns a NodeSet for //element queries" do
    books = doc.xpath("//book")
    expect(books).to be_a(Leptris::XML::NodeSet)
    expect(books.length).to eq(3)
  end

  it "returns a String for string() queries" do
    title = doc.xpath("string(//book[@id='1']/title)")
    expect(title).to eq("Ruby")
  end

  it "returns a Boolean for predicate-only queries" do
    # Uses boolean() which libleptris v0.5.5+ flat XPath dispatcher
    # correctly supports.
    expect(doc.xpath("boolean(//book)")).to be true
    expect(doc.xpath("boolean(//missing)")).to be false
  end

  # Regression for upstream libleptris #201 (fixed in v0.5.7): the v0.5.5
  # flat XPath dispatcher over-matched expressions starting with count(...),
  # returning the inner number rather than evaluating the full comparison.
  it "returns a Boolean for count(...) > N expressions" do
    expect(doc.xpath("count(//book) > 0")).to be true
    expect(doc.xpath("count(//missing) > 0")).to be false
    expect(doc.xpath("count(//book) > 5")).to be false
    expect(doc.xpath("count(//book) >= 3")).to be true
  end

  it "supports at_xpath returning the first match" do
    first_book = doc.at_xpath("//book")
    expect(first_book["id"]).to eq("1")
  end

  it "supports xpath on Element receiver (context-relative)" do
    second_book = doc.at_xpath("//book[@id='2']")
    title = second_book.xpath("title")
    expect(title).to be_a(Leptris::XML::NodeSet)
    expect(title.first.content).to eq("XML")
  end

  it "supports . at context node" do
    first_book = doc.at_xpath("//book")
    expect(first_book.xpath(".")).to be_a(Leptris::XML::NodeSet)
  end

  it "supports XPath on NodeSet (search each member)" do
    books = doc.xpath("//book")
    all_titles = books.xpath("title")
    expect(all_titles.length).to eq(3)
    expect(all_titles.map(&:content)).to eq(%w[Ruby XML XPath])
  end
end

RSpec.describe "upstream #630: relative namespaced descendant paths" do
  it "evaluates .//ns:x and descendant::ns:x from element context" do
    doc = Leptris::XML::Document.parse(
      %q{<r xmlns:x="urn:x"><a><x:b id="1"/></a><x:b id="2"/></r>})
    a = doc.root.element_children.first
    ns = { "x" => "urn:x" }
    expect(a.xpath(".//x:b", ns).map { |e| e["id"] }).to eq(%w[1])
    expect(a.xpath("descendant::x:b", ns).map { |e| e["id"] }).to eq(%w[1])
    expect(doc.xpath("//x:b", ns).map { |e| e["id"] }).to eq(%w[1 2])
  end
end

RSpec.describe "leptris-ruby#103: prefixed attribute predicate without a binding set" do
  it "resolves the prefix through the document's own declarations" do
    doc = Leptris::XML::Document.parse(
      %(<root xmlns:p="http://x.org"><item id="1" p:kind="a">alpha</item>) +
      %(<item id="2">beta</item></root>))
    expect(doc.xpath(%(//item[@id="2"])).size).to eq(1)
    expect(doc.xpath(%(//item[@p:kind="a"])).size).to eq(1)
    expect(doc.xpath(%(//item/@p:kind)).size).to eq(1)
  end
end

RSpec.describe "standalone XPath 2/3.1 expression subset (libleptris 1.9.35+)" do
  let(:doc) { Leptris::XML::Document.parse("<r><a>1</a><a>2</a></r>") }

  {
    "let … return (3.0)"        => ["let $x := 2 return $x + 1", 3.0],
    # for-return's items come back as opaque result nodes (not Text/
    # Element) — read them through an aggregate until the engine
    # materializes readable sequence items.
    "for … return (2.0)"        => ["count(for $i in //a return $i)", 2.0],
    "if/then/else (2.0)"        => ['if (count(//a) = 2) then "two" else "no"', "two"],
    "sequence literal (2.0)"    => ["count((1, 2, 3))", 3.0],
    "range expression (2.0)"    => ["count(1 to 4)", 4.0],
    "arrow operator (3.1)"      => ["//a => count()", 2.0],
    "simple map ! (3.1)"        => ["count(//a ! string(.))", 2.0],
    "string concat || (3.1)"    => ['"x" || "y"', "xy"],
  }.each do |label, (expr, expected)|
    it "evaluates #{label}" do
      result = doc.xpath(expr)
      expect(result.is_a?(Leptris::XML::NodeSet) ? result.to_a : result).to eq(expected)
    end
  end

  it "rejects XQuery-only FLWOR clauses outside a stylesheet (leptris/leptris#692)" do
    expect { doc.xpath("for $a in //a order by $a return $a") }
      .to raise_error(Leptris::XML::XPathError)
  end
end

RSpec.describe "XQuery 3.0 tail and fn: catalog slices (libleptris 1.9.77-1.9.79)" do
  let(:doc) do
    Leptris::XML::Document.parse(%q{<a><b id="1"/><c/><b id="2"/><c><d/></c></a>})
  end

  {
    "braceless switch"          => ["switch (2) case 1 return 'one' case 2 return 'two' default return 'other'", "two"],
    "array { } constructor"     => ["array { 1 to 3 }?2", "2"],
    "parse-xml document node"   => ["count(parse-xml('<r><x/><y/></r>')/*/*)", 2.0],
    "fn:innermost"              => ["count(innermost(//b | //c/d))", 3.0],
    "fn:outermost"              => ["count(outermost(//c/d))", 1.0],
    "fn:has-children (true)"    => ["has-children(//c[d])", true],
    "fn:has-children (false)"   => ["has-children(//b[1])", false],
    "fn:path positional form"   => ["path(//b[@id = '2'])", "/a/b[2]"],
    "fn:nilled"                 => ["nilled(//b[1])", false],
    "fn:base-uri (in-memory)"   => ["string(base-uri(/a))", ""],
    "fn:compare"                => ["compare('a', 'b')", -1.0],
    "fn:codepoint-equal"        => ["codepoint-equal('a', 'a')", true],
    "fn:round with precision"   => ["round(15, -1)", 20.0],
    "rng ?number seeded"        => ["random-number-generator(42)?number < 1", true],
  }.each do |label, (expr, expected)|
    it "evaluates #{label}" do
      expect(doc.xpath(expr)).to eq(expected)
    end
  end

  # fn:normalize-unicode needs utf8proc — compiled out of the
  # vendored platform builds (LEPTRIS_ENABLE_UTF8PROC=OFF).
  it "normalizes unicode where utf8proc is built in" do
    skip "utf8proc disabled in vendored builds — raises for the same reason"
    expect(doc.xpath("string-length(normalize-unicode('é'))")).to eq(1.0)
  end
end

RSpec.describe "fn:format-number standalone (libleptris 1.9.80)" do
  let(:doc) { Leptris::XML::Document.parse("<r/>") }

  {
    "grouping + decimals" => ["format-number(12345.678, '#,##0.00')", "12,345.68"],
    "percent"             => ["format-number(0.42, '0%')", "42%"],
    "zero padding"        => ["format-number(42, '00000')", "00042"],
  }.each do |label, (expr, expected)|
    it "formats #{label}" do
      expect(doc.xpath(expr)).to eq(expected)
    end
  end
end

RSpec.describe "fn:snapshot and fn:analyze-string (libleptris 1.9.81-1.9.82)" do
  let(:doc) { Leptris::XML::Document.parse(%q{<r><b id="1">x</b><b id="2">y</b></r>}) }

  it "deep-copies each input onto an anchored document (fn:snapshot)" do
    expect(doc.xpath("count(snapshot(//b))")).to eq(2.0)
    expect(doc.xpath("string(snapshot(//b)[2]/@id)")).to eq("2")
  end

  it "splits input into the fn:match / fn:non-match model (fn:analyze-string)" do
    skip "regex engine unavailable on MSVC builds" if Gem.win_platform?
    result = doc.xpath("analyze-string('a1b2c3', '[0-9]')")
    expect(result.size).to eq(1)
    expect(result.first.to_xml)
      .to include("<fn:match>1</fn:match>", "<fn:non-match>a</fn:non-match>")
    expect(doc.xpath("count(analyze-string('a1b2c3', '[0-9]')/*[local-name() = 'match'])")).to eq(3.0)
    expect(doc.xpath("string(analyze-string('a1b', '[0-9]'))")).to eq("a1b")
  end

  # 1.9.87 (#846): constructed elements are namespace-aware — the
  # analyze-string root DECLARES xmlns:fn, so prefixed tests select
  # under a bound fn prefix and namespace-uri() answers.
  it "selects analyze-string output with a bound fn prefix (libleptris 1.9.87, #846)" do
    skip "regex engine unavailable on MSVC builds" if Gem.win_platform?
    fn = { "fn" => "http://www.w3.org/2005/xpath-functions" }
    expect(doc.xpath("count(analyze-string('a1b2', '[0-9]')/fn:match)", fn)).to eq(2.0)
    expect(doc.xpath(
      "namespace-uri(analyze-string('a1', '[0-9]')/*[1])"))
      .to eq("http://www.w3.org/2005/xpath-functions")
    expect(doc.xpath("analyze-string('a1', '[0-9]')").first.to_xml)
      .to include('xmlns:fn="http://www.w3.org/2005/xpath-functions"')
  end
end

RSpec.describe "fn:analyze-string group spans (libleptris 1.9.89, leptris/leptris#857)" do
  let(:doc) { Leptris::XML::Document.parse("<r/>") }
  let(:fn) { { "fn" => "http://www.w3.org/2005/xpath-functions" } }

  it "reads group values at non-zero match offsets" do
    skip "regex engine unavailable on MSVC builds" if Gem.win_platform?
    result = doc.xpath("analyze-string('ab12cd', '([0-9]+)')", fn)
    expect(result.first.to_xml)
      .to include('<fn:match><fn:group nr="1">12</fn:group></fn:match>')
  end

  it "carries multi-group matches without cross-call contamination" do
    skip "regex engine unavailable on MSVC builds" if Gem.win_platform?
    expect(doc.xpath("count(analyze-string('x1y22z', '([a-z]+)([0-9]+)')/fn:match/fn:group)", fn))
      .to eq(4.0)
    expect(doc.xpath("count(analyze-string('a1', '[0-9]')/fn:match/fn:group)", fn))
      .to eq(0.0)
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

RSpec.describe "xs: atomic constructors and sequence-use keys (libleptris 1.9.47-1.9.49)" do
  it "constructs atomics from any expression (Saxon ground truth, 1.9.49)" do
    doc = Leptris::XML::Document.parse("<r><a v='1'>alpha</a></r>")
    expect(doc.xpath("xs:integer('42') + 1")).to eq(43.0)
    expect(doc.xpath("xs:double('1.5') * 2")).to eq(3.0)
    expect(doc.xpath("xs:decimal('2.5') + 1")).to eq(3.5)
    expect(doc.xpath("xs:boolean('true')")).to be(true)
    expect(doc.xpath("xs:string(7)")).to eq("7")
    expect(doc.xpath("xs:anyURI('urn:x')")).to eq("urn:x")
  end

  it "indexes every item of a sequence xsl:key use (#720 fixed in 1.9.47)" do
    expect(Leptris::XML::XSLT.parse(<<~XSL)
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:key name="k" match="a" use="@v, ."/>
        <xsl:template match="/"><out><xsl:value-of select="count(key('k','1'))"/>|<xsl:value-of select="count(key('k','alpha'))"/></out></xsl:template>
      </xsl:stylesheet>
    XSL
      .apply_to(Leptris::XML::Document.parse("<r><a v='1'>alpha</a></r>")).to_s)
      .to include("<out>1|1</out>")
  end
end

RSpec.describe "XPath 2.0 type operators standalone (libleptris 1.9.50)" do
  let(:doc) { Leptris::XML::Document.parse("<r><a>1</a></r>") }

  {
    "'42' castable as xs:integer" => true,
    "'x' castable as xs:integer"  => false,
    "1.9 cast as xs:integer"      => 1.0,
    "1 treat as xs:integer"       => 1.0,
    "//a instance of node()+"     => true,
    "'s' instance of xs:string"   => true,
    "1 instance of xs:double"     => true,
  }.each do |expr, expected|
    it "evaluates #{expr}" do
      expect(doc.xpath(expr)).to eq(expected)
    end
  end

  it "casts through the constructor semantics (xs:integer truncates toward zero)" do
    expect(doc.xpath("-1.9 cast as xs:integer")).to eq(-1.0)
  end

  # Known edges, not specced as expectations: sequence literals come
  # back as opaque result nodes so `(1,2) instance of xs:integer+`
  # answers over nodes, and an invalid `cast as` returns instead of
  # raising FORG0001 — both tracked with the #683 grammar work.
end

RSpec.describe "Node#digest (libleptris 1.9.99, leptris/leptris#869)" do
  it "matches for structurally-equal subtrees and differs for differing content" do
    d1 = Leptris::XML::Document.parse(%q{<r><a x="1">hi<b/></a></r>}).root
    d3 = Leptris::XML::Document.parse(%q{<r><a x="1">hi<b/></a></r>}).root
    d_other_child = Leptris::XML::Document.parse(%q{<r><a x="1">hi<c/></a></r>}).root
    d_p_c = Leptris::XML::Document.parse(%q{<r xmlns:p="urn:p"><p:c/></r>}).root
    d_p_d = Leptris::XML::Document.parse(%q{<r xmlns:p="urn:p"><p:d/></r>}).root
    expect(d1.digest).to eq(d3.digest)
    expect(d1.digest).not_to eq(d_other_child.digest)
    expect(d_p_c.digest).not_to eq(d_p_d.digest)
  end
end
