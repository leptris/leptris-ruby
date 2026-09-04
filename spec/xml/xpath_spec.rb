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

  it "evaluates braceless switch in the XQuery face" do
    expect(Leptris::XML::XQuery.parse(
      "switch (1) case 1 return 'uno' default return 'other'").eval(doc))
      .to eq("uno")
  end

  # fn:normalize-unicode needs utf8proc — compiled out of the
  # vendored platform builds (LEPTRIS_ENABLE_UTF8PROC=OFF).
  it "normalizes unicode where utf8proc is built in" do
    skip "utf8proc disabled in vendored builds — raises for the same reason"
    expect(doc.xpath("string-length(normalize-unicode('é'))")).to eq(1.0)
  end
end
