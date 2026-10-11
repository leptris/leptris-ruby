# frozen_string_literal: true

require "spec_helper"


# moxml#354 / leptris#1635: to_html indentation through the ext
# serializer — the libxml2 format model (single-child elements stay
# inline, raw-text verbatim, no declaration).
RSpec.describe "Document#to_html indentation (moxml#354)" do
  # The nested layout rides the engine's indent_html ext option
  # (leptris#1637). Against a pre-#1637 vendored engine the ext
  # serializer keeps the §16.2 newline-only bytes — the probe arms
  # the byte-pinning legs exactly when the ride lands.
  def self.engine_carries_1637?
    @engine_carries_1637 ||=
      Leptris::HTML.parse("<html><body><div><p>x</p><p>y</p></div></body></html>")
        .to_html(indent: 2).include?("\n  ")
  end

  let(:doc) do
    Leptris::HTML.parse(
      "<html><head><title>T</title></head><body><div id=\"a\"><p>x</p>" \
      "<span>y</span></div><script>if (a < b) { c(); }</script></body></html>")
  end

  it "stays single-line-shaped without indent kwargs" do
    expect(doc.to_html).not_to include("\n  ")
    expect(doc.to_html).to start_with("<html>")
  end

  before do
    skip "vendored engine predates leptris#1637" unless self.class.engine_carries_1637?
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
