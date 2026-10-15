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

RSpec.describe "Document#to_xml on HTML documents" do
  def parse_xml_strict(xml)
    previous_mode = Leptris::XML::FFI.leptris_get_strict_mode
    begin
      Leptris::XML::FFI.leptris_set_strict_mode(1)
      Leptris::XML.parse(xml)
    ensure
      Leptris::XML::FFI.leptris_set_strict_mode(previous_mode)
    end
  end

  let(:source) do
    '<p>a &amp; b < c; &lt; d</p><script>y = "</q>"; a & b;</script>' \
      '<style>a > b { content: "<x> & y"; }</style><br><input disabled>'
  end

  [:html4, :whatwg].each do |mode|
    context "with #{mode} parsing" do
      let(:doc) { Leptris::XML.parse_html(source, mode: mode) }

      [
        {},
        { indent: 2, no_decl: true, encoding: "UTF-8" },
        { indent: 1, indent_text: "\t", no_decl: true },
        { indent: 2, indent_text: true, no_decl: true },
      ].each do |options|
        it "emits XML escaping and closed voids with #{options.inspect}" do
          out = doc.to_xml(**options)
          expect(out).to include('y = "&lt;/q&gt;"; a &amp; b;')
          expect(out).to include("&lt;x&gt; &amp; y")
          expect(out).to include("<br/>")
          expect(out).to include('disabled=""')
          expect(out).not_to include("&amp;amp;", "&amp;lt;")
          expect(out.start_with?("<?xml")).to eq(!options.fetch(:no_decl, false))
          reparsed = parse_xml_strict(out)
          %w[p script style].each do |name|
            # The display form intentionally adds text indentation.
            expect(reparsed.at_css(name).content.strip)
              .to eq(doc.at_css(name).content.strip)
          end
        end
      end

      it "keeps HTML output and element XML output after document XML serialization" do
        html = doc.to_html
        element_xml = doc.root.to_xml
        doc.to_xml
        expect(doc.to_html).to eq(html)
        expect(doc.root.to_xml).to eq(element_xml)
        expect(html).to include("<br>", 'y = "</q>"; a & b;')
        expect(html).not_to include("<br/>")
        expect(element_xml).to include("<br/>", 'y = "&lt;/q&gt;"; a &amp; b;')
      end
    end
  end
end
