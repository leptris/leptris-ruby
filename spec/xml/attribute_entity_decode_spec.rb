# frozen_string_literal: true

# XML 1.0 §4.6: character references decode in attribute values
# exactly as in content. Every consumer-facing attribute surface
# must serve the DECODED value — the raw source views belong to
# Element#attributes_raw (#635), not to these faces. Discovered via
# lutaml/moxml#540: the listing faces served raw views and the
# XSD unicode-block pattern cases (attribute values full of
# &#x2190;-style arrows) flipped to failing.
RSpec.describe "native attribute faces decode character references" do
  let(:xml) { '<r a="&#x2190;" b="&amp;&lt;" c="&unknown;" d="plain"/>' }
  let(:doc) { Leptris::XML::Document.parse(xml) }
  let(:root) { doc.root }
  # The accessor is the reference semantics: numeric + predefined
  # refs decode; unknown named entities stay literal.
  let(:expected) do
    [["a", "←"], ["b", "&<"], ["c", "&unknown;"], ["d", "plain"]]
  end

  it "the accessor decodes (reference semantics)" do
    expect(root["a"]).to eq("←")
    expect(root["b"]).to eq("&<")
    expect(root["c"]).to eq("&unknown;")
  end

  it "attribute_pairs serves decoded values" do
    expect(root.attribute_pairs).to eq(expected)
  end

  describe "the native faces" do
    let(:root_addr) { root.c_address }

    it "attribute_packet serves decoded values" do
      skip unless Leptris::XML::Native.respond_to?(:attribute_packet)
      flat = Leptris::XML::Native.attribute_packet(doc, root_addr)
      pairs = flat.each_slice(2).to_a
      expect(pairs).to eq(expected)
    end

    it "attribute_pairs (native) serves decoded values" do
      skip unless Leptris::XML::Native.respond_to?(:attribute_pairs)
      flat = Leptris::XML::Native.attribute_pairs(doc, root_addr)
      pairs = flat.each_slice(2).to_a
      expect(pairs).to eq(expected)
    end

    it "attribute_rows serves decoded values" do
      skip unless Leptris::XML::Native.respond_to?(:attribute_rows)
      flat = Leptris::XML::Native.attribute_rows(doc, root_addr)
      # triples: [name, value, attr-address]
      got = flat.each_slice(3).map { |(n, v, _)| [n, v] }
      expect(got).to eq(expected)
    end
  end
end
