# frozen_string_literal: true

require "spec_helper"

# Stylesheet top-level params (#360): params: threads a Hash of
# name => value through leptris_xslt_apply_params — supplied names
# never evaluate select/@default; values bind as XPath strings
# (caller owns numeric quoting, nokogiri quote_params conventions).
RSpec.describe "Stylesheet params (#360)" do
  let(:sheet_src) do
    <<~XSL
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:param name="n" select="'D'"/>
        <xsl:template match="/">
          <v><xsl:value-of select="$n"/></v>
        </xsl:template>
      </xsl:stylesheet>
    XSL
  end
  let(:doc) { Leptris::XML::Document.parse(%(<r/>)) }

  it "overrides a top-level param through apply_to" do
    sheet = Leptris::XML::XSLT.parse(sheet_src)
    out = sheet.apply_to(doc, params: { "n" => "7" })
    expect(out.root.content).to eq("7")
  end

  it "keeps the default when the name is absent" do
    sheet = Leptris::XML::XSLT.parse(sheet_src)
    expect(sheet.apply_to(doc).root.content).to eq("D")
    expect(sheet.apply_to(doc, params: { "other" => "x" }).root.content)
      .to eq("D")
  end

  it "threads params through serialize (quoted string literals)" do
    sheet = Leptris::XML::XSLT.parse(sheet_src)
    expect(sheet.serialize(doc, params: { "n" => "'S'" }))
      .to include("<v>S</v>")
  end

  it "handles multiple params and skips unknown names" do
    src = <<~XSL
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:param name="a" select="'DA'"/>
        <xsl:param name="b" select="'DB'"/>
        <xsl:template match="/"><w a="{$a}" b="{$b}"/></xsl:template>
      </xsl:stylesheet>
    XSL
    sheet = Leptris::XML::XSLT.parse(src)
    out = sheet.serialize(doc, params: { "a" => "1" })
    expect(out).to include(%(a="1")).and include(%(b="DB"))
  end

  it "evaluates values as XPath expressions (engine 1.9.288+)" do
    src = <<~XSL
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:param name="n"/>
        <xsl:template match="/">
          <i><xsl:value-of select="$n + 1"/></i>
        </xsl:template>
      </xsl:stylesheet>
    XSL
    sheet = Leptris::XML::XSLT.parse(src)
    out = sheet.apply_to(doc, params: { "n" => "6" })   # expression: number
    expect(out.root.content).to eq("7")
    out2 = sheet.apply_to(doc, params: { "n" => "4 * 3" })
    expect(out2.root.content).to eq("13")
  end

  it "rejects non-Hash params" do
    sheet = Leptris::XML::XSLT.parse(sheet_src)
    expect { sheet.apply_to(doc, params: [%w[n 7]]) }
      .to raise_error(ArgumentError, /Hash/)
  end
end
