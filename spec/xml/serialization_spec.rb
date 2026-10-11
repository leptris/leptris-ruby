# frozen_string_literal: true

require "spec_helper"


# moxml#354 / leptris#1635: to_html indentation through the ext
# serializer — the libxml2 format model (single-child elements stay
# inline, raw-text verbatim, no declaration).
RSpec.describe "Document#to_html indentation (moxml#354)" do
  let(:doc) do
    Leptris::HTML.parse(
      "<html><head><title>T</title></head><body><div id=\"a\"><p>x</p>" \
      "<span>y</span></div><script>if (a < b) { c(); }</script></body></html>")
  end

  it "stays single-line-shaped without indent kwargs" do
    expect(doc.to_html).not_to include("\n  ")
    expect(doc.to_html).to start_with("<html>")
  end

  it "nests with space indent" do
    out = doc.to_html(indent: 2)
    expect(out).to include("<html>\n  <head><title>T</title></head>")
    expect(out).to include("<body>\n    <div id=\"a\">\n      <p>x</p>")
    expect(out).to include("    </div>\n")
    expect(out).not_to start_with("<?xml")
  end

  it "nests with the indent_text unit" do
    out = doc.to_html(indent: 1, indent_text: "\t")
    expect(out).to include("<body>\n\t\t<div id=\"a\">\n\t\t\t<p>x</p>")
  end

  it "keeps raw-text script content verbatim" do
    out = doc.to_html(indent: 2)
    expect(out).to include("<script>if (a < b) { c(); }</script>\n  </body>")
  end
end
