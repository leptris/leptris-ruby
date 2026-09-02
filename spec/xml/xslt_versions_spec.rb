# frozen_string_literal: true

RSpec.describe "XSLT 1.0–3.0 through the generic parse/apply face" do
  it "transforms XSLT 1.0 stylesheets" do
    sheet = <<~XSL
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:template match="/">
          <out><xsl:value-of select="count(//item)"/></out>
        </xsl:template>
      </xsl:stylesheet>
    XSL
    doc = Leptris::XML::Document.parse("<r><item/><item/></r>")
    result = Leptris::XML::XSLT.parse(sheet).apply_to(doc)
    expect(result.root.to_xml).to eq("<out>2</out>")
  end

  it "transforms XSLT 3.0 stylesheets (let, arrow — the 3.1 core)" do
    sheet = <<~XSL
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/">
          <out>
            <xsl:value-of select="let $x := 21 return $x => string() => concat('!')"/>
            <xsl:value-of select="string-join((1 to 3), ',')"/>
          </out>
        </xsl:template>
      </xsl:stylesheet>
    XSL
    result = Leptris::XML::XSLT.parse(sheet)
      .apply_to(Leptris::XML::Document.parse("<r/>"))
    expect(result.root.to_xml).to eq("<out>21!1,2,3</out>")
  end

  it "runs xsl:analyze-string where the regex engine is available" do
    # libleptris 1.9.25: analyze-string no-ops on MSVC (the POSIX
    # ERE engine limitation, same as the EXSLT regexp handlers).
    skip "analyze-string no-ops on MSVC builds" if Gem.win_platform?
    sheet = <<~XSL
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/">
          <out>
            <xsl:analyze-string select="'a1b2'" regex="[0-9]">
              <xsl:matching-substring><d><xsl:value-of select="."/></d></xsl:matching-substring>
              <xsl:non-matching-substring><c><xsl:value-of select="."/></c></xsl:non-matching-substring>
            </xsl:analyze-string>
          </out>
        </xsl:template>
      </xsl:stylesheet>
    XSL
    result = Leptris::XML::XSLT.parse(sheet)
      .apply_to(Leptris::XML::Document.parse("<r/>"))
    expect(result.root.to_xml).to eq("<out><c>a</c><d>1</d><c>b</c><d>2</d></out>")
  end
end

RSpec.describe "XSLT 3.0 completion (libleptris 1.9.33-1.9.43)" do
  HITS_ONLY = %q[<?xml version="1.0"?><hit/>].freeze
  EMPTY = "".freeze
  def transform(sheet, source = "<r><a>3</a><a>1</a><a>2</a></r>")
    Leptris::XML::XSLT.parse(sheet)
      .apply_to(Leptris::XML::Document.parse(source)).to_s
  end

  it "evaluates xsl:sequence (1.9.35)" do
    expect(transform(<<~XSL)).to include("<out>1 2 3</out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:sequence select="(1 to 3)"/></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "evaluates xsl:perform-sort (1.9.35)" do
    expect(transform(<<~XSL)).to include("<out><a>1</a><a>2</a><a>3</a></out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out>
          <xsl:perform-sort select="//a"><xsl:sort select="."/></xsl:perform-sort>
        </out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  {
    "shallow-copy" => %q[<?xml version="1.0"?><r><a>3</a><hit/><a>2</a></r>],
    "deep-copy"    => %q[<?xml version="1.0"?><r><a>3</a><a>1</a><a>2</a></r>],
    "deep-skip"    => "",
  }.each do |disposition, expected|
    it "applies xsl:mode on-no-match=\"#{disposition}\" (1.9.33)" do
      expect(transform(<<~XSL)).to eq(expected)
        <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
          <xsl:mode on-no-match="#{disposition}"/>
          <xsl:template match="/r/a[2]"><hit/></xsl:template>
        </xsl:stylesheet>
      XSL
    end
  end

  it "raises for xsl:mode on-no-match=\"fail\" when a node goes unmatched (1.9.33)" do
    expect { transform(<<~XSL) }.to raise_error(Leptris::XML::XPathError)
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:mode on-no-match="fail"/>
      </xsl:stylesheet>
    XSL
  end

  # Saxon-HE 12.7 parity, verified upstream (leptris/leptris#705
  # fixed in 1.9.37): the no-template case emits EMPTY for BOTH
  # dispositions (the report's "312" expectation for shallow-skip
  # contradicted Saxon), and with a child template the unmatched
  # siblings contribute nothing — their text nodes take the mode's
  # disposition too.
  {
    "shallow-skip"   => { child: HITS_ONLY, none: EMPTY, root: %q[<?xml version="1.0"?><out/>] },
    "text-only-copy" => { child: HITS_ONLY, none: EMPTY, root: %(<?xml version="1.0"?><out>312</out>) },
  }.each do |disposition, expected|
    it "applies xsl:mode on-no-match=\"#{disposition}\" (leptris/leptris#705)" do
      expect(transform(<<~XSL)).to eq(expected[:child])
        <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
          <xsl:mode on-no-match="#{disposition}"/>
          <xsl:template match="/r/a[2]"><hit/></xsl:template>
        </xsl:stylesheet>
      XSL
      expect(transform(<<~XSL)).to eq(expected[:none])
        <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
          <xsl:mode on-no-match="#{disposition}"/>
        </xsl:stylesheet>
      XSL
      expect(transform(<<~XSL)).to eq(expected[:root])
        <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
          <xsl:mode on-no-match="#{disposition}"/>
          <xsl:template match="/"><out><xsl:apply-templates/></out></xsl:template>
        </xsl:stylesheet>
      XSL
    end
  end

  it "evaluates fn:format-integer (1.9.36: bijective base-26, roman numerals)" do
    expect(transform(<<~XSL)).to include("<out>Z|MMXXIV</out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out>
          <xsl:value-of select="format-integer(26,'A')"/>|<xsl:value-of select="format-integer(2024,'I')"/>
        </out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "rejects XQuery-only syntax in XPath expressions (1.9.34, leptris/leptris#692)" do
    expect { transform(<<~XSL) }.to raise_error(Leptris::XML::XPathError)
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:value-of select="for $a in //a order by $a return $a"/></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end
end

RSpec.describe "XSLT 3.0 additions (libleptris 1.9.37-1.9.43)" do
  def transform(sheet, source = "<r><a>3</a><a>1</a><a>2</a></r>")
    Leptris::XML::XSLT.parse(sheet)
      .apply_to(Leptris::XML::Document.parse(source)).to_s
  end

  it "passes tunnel parameters through the subtree (1.9.37, §11.7)" do
    expect(transform(<<~XSL)).to include("<out><v>T</v><v>T</v><v>T</v></out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out>
          <xsl:apply-templates select="//a"><xsl:with-param name="t" tunnel="yes" select="'T'"/></xsl:apply-templates>
        </out></xsl:template>
        <xsl:template match="a"><xsl:param name="t" tunnel="yes"/><v><xsl:value-of select="$t"/></v></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "serializes a single-item atomic xsl:sequence (1.9.38)" do
    expect(transform(<<~XSL)).to include("<out>42</out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:sequence select="42"/></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "atomizes node arguments in the regex trio (1.9.38)" do
    skip "regex engine unavailable on MSVC builds" if Gem.win_platform?
    expect(transform(<<~XSL)).to include("<out>true</out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:value-of select="matches(//a[1], '3')"/></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "evaluates the fn: date slice (1.9.40, #691-E)" do
    expect(transform(<<~XSL)).to include("<out>2026-10</out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out>
          <xsl:value-of select="year-from-dateTime(xs:dateTime('2026-09-01T10:30:00'))"/>-<xsl:value-of select="hours-from-time(xs:time('10:30:00'))"/>
        </out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "drops a wholly-empty where-populated build but keeps a populated one (1.9.42, §26.2)" do
    expect(transform(<<~XSL)).to include("<out>|<full>3</full></out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out>
          <xsl:where-populated><xsl:value-of select="//nothing"/></xsl:where-populated>|<xsl:where-populated><full><xsl:value-of select="count(//a)"/></full></xsl:where-populated>
        </out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "falls back through xsl:next-match to the lower-priority rule (1.9.42, §6.6)" do
    expect(transform(<<~XSL)).to include("{3}A2[{1}]{2}")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/r/a[2]">A2[<xsl:next-match/>]</xsl:template>
        <xsl:template match="a">{<xsl:value-of select="."/>}</xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "runs xsl:fork arms sequentially (1.9.43, §14)" do
    expect(transform(<<~XSL)).to include("<out>3 x</out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:fork><xsl:sequence select="count(//a)"/><xsl:sequence select="'x'"/></xsl:fork></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "offsets xsl:number with @start-at (1.9.43, §12.2)" do
    expect(transform(<<~XSL)).to include("<out>10 11 12 </out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:for-each select="//a"><xsl:number start-at="10"/><xsl:text> </xsl:text></xsl:for-each></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "indexes nodes under each whitespace-separated composite key token (1.9.43, §12.2)" do
    expect(transform(<<~XSL)).to include("<out>3|3|0</out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:key name="k" match="a" use="'x y'"/>
        <xsl:template match="/"><out>
          <xsl:value-of select="count(key('k','x'))"/>|<xsl:value-of select="count(key('k','y'))"/>|<xsl:value-of select="count(key('k','z'))"/>
        </out></xsl:template>
      </xsl:stylesheet>
    XSL
  end
end

RSpec.describe "XSLT additions (libleptris 1.9.44-1.9.46)" do
  def transform(sheet, source = "<r/>")
    Leptris::XML::XSLT.parse(sheet)
      .apply_to(Leptris::XML::Document.parse(source)).to_s
  end

  it "copies selected items with xsl:copy @select (1.9.44, §9.9.2)" do
    expect(transform(<<~XSL, "<r><a x='1'><c/></a><b/></r>")).to include('<copy x="1"/>')
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/r/a"><copy><xsl:copy select="@*"/></copy></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "binds namespaces with xsl:namespace (1.9.44, §11.7)" do
    expect(transform(<<~XSL)).to include('<e xmlns:n="urn:n">body</e>')
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
        <xsl:template match="/"><out><xsl:element name="e"><xsl:namespace name="n">urn:n</xsl:namespace><xsl:value-of select="'body'"/></xsl:element></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "flows xsl:document content to the pending parent (1.9.44, §11.8)" do
    expect(transform(<<~XSL)).to include("<out><d>inner</d></out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
        <xsl:template match="/"><out><xsl:document><d>inner</d></xsl:document></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "evaluates xsl:param @default when no with-param binds (1.9.44)" do
    expect(transform(<<~XSL)).to include("<t1>passed</t1><t2>fallback</t2>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><wrap>
          <t1><xsl:call-template name="f"><xsl:with-param name="v" select="'passed'"/></xsl:call-template></t1>
          <t2><xsl:call-template name="f"/></t2>
        </wrap></xsl:template>
        <xsl:template name="f"><xsl:param name="v" default="'fallback'"/><xsl:value-of select="$v"/></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "threads params through xsl:iterate + xsl:next-iteration (1.9.45)" do
    expect(transform(<<~XSL)).to include('<final sum="10"/>')
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:iterate select="1 to 4">
          <xsl:param name="sum" select="0"/>
          <xsl:if test=". = 4"><final sum="{$sum + .}"/></xsl:if>
          <xsl:next-iteration><xsl:with-param name="sum" select="$sum + ."/></xsl:next-iteration>
        </xsl:iterate></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "evaluates dynamic XPath with xsl:evaluate (1.9.45, §14.3)" do
    expect(transform(<<~XSL, "<r><a>7</a></r>")).to include("<out>14</out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:evaluate xpath="number(//a) * 2"/></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "writes xsl:result-document to the href file, principal result unchanged (1.9.46, §11.8)" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "side.xml")
      out = transform(<<~XSL, "<r><a/><a/></r>")
        <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
          <xsl:template match="/"><main/><xsl:result-document href="#{path}"><side><xsl:value-of select="count(//a)"/></side></xsl:result-document></xsl:template>
        </xsl:stylesheet>
      XSL
      expect(out).to include("<main/>")
      expect(File.read(path)).to include("<side>2</side>")
    end
  end

  # Character maps ride the stylesheet's xsl:output, so they apply
  # through XSLT#serialize (the engine's output-aware serializer) —
  # NOT through apply_to(doc).to_s, which re-serializes via the
  # plain document face and knows nothing of xsl:output.
  it "substitutes characters via xsl:character-map (1.9.46, §16.1)" do
    style = Leptris::XML::XSLT.parse(<<~XSL)
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
        <xsl:character-map name="m"><xsl:output-character character="&#955;" string="lambda"/></xsl:character-map>
        <xsl:output use-character-maps="m"/>
        <xsl:template match="/"><xsl:copy-of select="//o"/></xsl:template>
      </xsl:stylesheet>
    XSL
    out = style.serialize(Leptris::XML::Document.parse("<r><o>λ</o></r>"))
    expect(out).to include("<o>lambda</o>")
  end

  it "groups and joins xsl:merge sources (1.9.45, §14.3; #731 fixed in 1.9.48)" do
    expect(transform(<<~XSL)).to include("<m>a1|1+0</m><m>a2|0+1</m><m>a3|1+1</m>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:variable name="L" select="('a1', 'a3')"/>
        <xsl:variable name="R" select="('a2', 'a3')"/>
        <xsl:template match="/"><out><xsl:merge>
          <xsl:merge-source name="l" select="$L"/><xsl:merge-source name="r" select="$R"/>
          <xsl:merge-key select="string(.)"/>
          <xsl:merge-action><m><xsl:value-of select="current-merge-key()"/>|<xsl:value-of select="count(current-merge-group('l'))"/>+<xsl:value-of select="count(current-merge-group('r'))"/></m></xsl:merge-action>
        </xsl:merge></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  # §14.3.2 as triaged upstream (#730): the with-param channel
  # binds the DYNAMIC phase — @xpath must be a quoted expression
  # (Saxon rejects the unquoted outer-scope reference statically,
  # and so does the engine).
  it "binds xsl:evaluate with-params to the dynamic evaluation (1.9.45, §14.3.2)" do
    expect(transform(<<~XSL, "<r><a>7</a></r>")).to include("<out>7</out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:evaluate xpath="'$p'"><xsl:with-param name="p" select="string(//a)"/></xsl:evaluate></out></xsl:template>
      </xsl:stylesheet>
    XSL
    expect { transform(<<~XSL, "<r><a>7</a></r>") }
      .to raise_error(Leptris::XML::XPathError)
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:evaluate xpath="$p"><xsl:with-param name="p" select="string(//a)"/></xsl:evaluate></out></xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "sees the final iterate params in xsl:on-completion (1.9.44, §12.5; #729 fixed in 1.9.48)" do
    expect(transform(<<~XSL)).to include("<out>10</out>")
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/"><out><xsl:iterate select="1 to 4">
          <xsl:param name="sum" select="0"/>
          <xsl:next-iteration><xsl:with-param name="sum" select="$sum + ."/></xsl:next-iteration>
          <xsl:on-completion><xsl:value-of select="$sum"/></xsl:on-completion>
        </xsl:iterate></out></xsl:template>
      </xsl:stylesheet>
    XSL
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
