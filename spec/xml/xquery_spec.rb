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

  RSpec.describe "XQuery grammar tail (libleptris 1.9.77)" do
  it "evaluates braceless switch" do
    doc = Leptris::XML::Document.parse("<r/>")
    expect(Leptris::XML::XQuery.parse(
      "switch (1) case 1 return 'uno' default return 'other'").eval(doc))
      .to eq("uno")
  end
end
