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
