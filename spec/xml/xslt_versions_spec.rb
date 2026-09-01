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

RSpec.describe "XSLT 3.0 completion (libleptris 1.9.33-1.9.36)" do
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

  %w[shallow-skip text-only-copy].each do |disposition|
    it "descends through on-no-match=\"#{disposition}\"" do
      skip "upstream leptris/leptris#705 drops unmatched subtrees in the built-in descent"
      expect(transform(<<~XSL)).to eq(%q[<?xml version="1.0"?>3<hit/>2])
        <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
          <xsl:mode on-no-match="#{disposition}"/>
          <xsl:template match="/r/a[2]"><hit/></xsl:template>
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
