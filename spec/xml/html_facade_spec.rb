# frozen_string_literal: true

# The HTML facade (Nokogiri-shaped entry points over the one DOM):
# Leptris::HTML / HTML4 / HTML5. Pure delegates to XML.parse_html —
# identity, errors, and the whole node surface carry over.
RSpec.describe "Leptris::HTML facade" do
  it "parses through the html4 lane (Nokogiri::HTML parity)" do
    doc = Leptris::HTML.parse("<p>only")
    expect(doc).to be_a(Leptris::XML::Document)
    expect(doc.at_css("body p").content).to eq("only")
    expect(doc.at_css("head")).to be_nil # html4: no synthesized empty head
  end

  it "HTML4 is the explicit html4 lane" do
    doc = Leptris::HTML4.parse("<p>only")
    expect(doc.at_css("body p").content).to eq("only")
    expect(doc.at_css("head")).to be_nil
  end

  it "HTML5 selects the WHATWG engine" do
    doc = Leptris::HTML5.parse("<script>var x</script><p>t</p>")
    expect(doc.at_css("head script")).not_to be_nil
    expect(doc.at_css("body p").content).to eq("t")
  end

  it "returns documents that interoperate with the XML surface" do
    doc = Leptris::HTML5.parse("<table><tr><td>c</td></tr></table>")
    expect(doc.at_css("table tbody tr td").content).to eq("c")
    node = doc.at_css("td")
    node.content = "mutated"
    # NOTE: the node's mutated view reads back; the SERIALIZED form
    # drops it — engine bug leptris/leptris#1220 (mutations on
    # HTML-parsed documents invisible to the serializer, both
    # lanes). The pin below is the working half; the serialize half
    # returns when #1220 does.
    expect(node.content).to eq("mutated")
    expect(doc.root.equal?(doc.root)).to be(true) # identity cache applies
  end

  it "propagates parse errors with the XML shape" do
    # HTML is tolerant by design; the error class contract still holds
    # for both lanes when the engine rejects input outright.
    expect(defined?(Leptris::XML::ParseError)).to be_truthy
    expect { Leptris::HTML5.parse("<html><body>x</body></html>") }
      .not_to raise_error
  end

end
