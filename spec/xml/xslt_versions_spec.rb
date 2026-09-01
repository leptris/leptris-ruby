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

  it "transforms XSLT 3.0 stylesheets (analyze-string, let, arrow)" do
    sheet = <<~XSL
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
        <xsl:template match="/">
          <out>
            <xsl:analyze-string select="'a1b2'" regex="[0-9]">
              <xsl:matching-substring><d><xsl:value-of select="."/></d></xsl:matching-substring>
              <xsl:non-matching-substring><c><xsl:value-of select="."/></c></xsl:non-matching-substring>
            </xsl:analyze-string>
            <xsl:value-of select="let $x := 21 return $x => string() => concat('!')"/>
          </out>
        </xsl:template>
      </xsl:stylesheet>
    XSL
    result = Leptris::XML::XSLT.parse(sheet)
      .apply_to(Leptris::XML::Document.parse("<r/>"))
    expect(result.root.to_xml)
      .to eq("<out><c>a</c><d>1</d><c>b</c><d>2</d>21!</out>")
  end
end
