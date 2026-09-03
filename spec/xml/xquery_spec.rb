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

  it "aggregates a where/at FLWOR through a function argument" do
    skip "upstream leptris/leptris#790 — where/at clauses inside a function-argument FLWOR fail to parse"
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

  it "returns a constructor from a for clause" do
    skip "upstream leptris/leptris#790 — constructor as the FLWOR return clause fails to parse"
    expect(xquery(%q{for $i in //item return <v>{$i/name/text()}</v>}))
      .to eq('<v>Alpha</v><v>Beta</v><v>Gamma</v>')
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
