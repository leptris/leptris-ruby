# frozen_string_literal: true

require "tmpdir"

require "spec_helper"

RSpec.describe Leptris::XML::XSLT do
  let(:doc) do
    Leptris::XML.parse(<<~XML)
      <catalog>
        <item id="1" price="30">alpha</item>
        <item id="2" price="50">beta</item>
        <item id="3" price="10">gamma</item>
      </catalog>
    XML
  end

  let(:style) do
    described_class.parse(<<~XSL)
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:template match="/">
          <summary total="{sum(//item/@price)}" count="{count(//item)}">
            <xsl:for-each select="//item">
              <line id="{@id}"><xsl:value-of select="."/></line>
            </xsl:for-each>
          </summary>
        </xsl:template>
      </xsl:stylesheet>
    XSL
  end

  it "compiles once and applies to documents" do
    result = style.apply_to(doc)
    expect(result).to be_a(Leptris::XML::Document)
    expect(result.root.name).to eq("summary")
    expect(result.root["total"]).to eq("90")
    expect(result.root["count"]).to eq("3")
    expect(result.root.xpath("//line").map(&:content)).to eq(%w[alpha beta gamma])
    expect(result.root.xpath("//line").map { |l| l["id"] }).to eq(%w[1 2 3])
  end

  it "applies the same compiled stylesheet to many documents" do
    other = Leptris::XML.parse("<catalog><item price=\"7\">x</item></catalog>")
    expect(style.apply_to(other).root["total"]).to eq("7")
    expect(style.apply_to(doc).root["total"]).to eq("90") # source unchanged
  end

  it "serializes fragments through apply_string" do
    fragment_style = described_class.parse(<<~XSL)
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:template match="//item"><xsl:value-of select="@id"/> </xsl:template>
        <xsl:template match="text()"/>
      </xsl:stylesheet>
    XSL
    out = fragment_style.serialize(doc)
    # Binding contract: the engine's serialized result as a UTF-8
    # String. (Whitespace around the emitted values follows the
    # engine's built-in template rules — not pinned here.)
    body = out.sub(/\A<\?xml[^>]*\?>/, "")
    expect(out.encoding).to eq(Encoding::UTF_8)
    expect(body.scan(/\d/)).to eq(%w[1 2 3])
  end

  it "raises on stylesheet syntax errors" do
    expect { described_class.parse("<xsl:stylesheet") }
      .to raise_error(Leptris::XML::XPathError, /parse failed/)
  end

  it "rejects bad select expressions at COMPILE time" do
    # The engine compiles select/test expressions when the stylesheet
    # parses — a bad XPath never reaches apply.
    expect {
      described_class.parse(<<~XSL)
        <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
          <xsl:template match="/"><xsl:value-of select="cause[('/'/0]"/></xsl:template>
        </xsl:stylesheet>
      XSL
    }.to raise_error(Leptris::XML::XPathError, /parse failed/)
  end

  it "loads stylesheets from a file" do
    path = File.join(Dir.mktmpdir, "style.xsl")
    File.write(path, <<~XSL)
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:template match="/"><done/></xsl:template>
      </xsl:stylesheet>
    XSL
    expect(described_class.parse_file(path).apply_to(doc).root.name).to eq("done")
  end

  it "leaves the source document untouched" do
    before = doc.to_xml(no_decl: true)
    style.apply_to(doc)
    expect(doc.to_xml(no_decl: true)).to eq(before)
  end
end
