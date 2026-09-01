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
