# frozen_string_literal: true

# leptris#1781 — nokogiri-parity gaps on DocumentFragment:
# 1. the serialization face (to_html / to_xml / to_s): a fragment
#    serializes as its children, concatenated — the synthetic
#    "#document-fragment" wrapper never emits.
# 2. DocumentFragment.parse with a nil/non-Document second argument
#    names the contract (the host Leptris::XML::Document) instead of
#    surfacing "document has been freed" from the native face.

RSpec.describe Leptris::XML::DocumentFragment do
  let(:doc) { Leptris::XML::Document.parse("<r/>") }

  describe "the serialization face" do
    it "serializes children concatenated, without the wrapper" do
      frag = described_class.parse("<a>1</a><!--c--><b x=\"2\"/>", doc)
      expect(frag.to_html).to eq(%(<a>1</a><!--c--><b x="2"/>))
      expect(frag.to_xml).to eq(frag.to_html)
      expect(frag.to_s).to eq(frag.to_html)
    end

    it "serializes text and nested markup" do
      frag = described_class.parse("hello <em>world</em>", doc)
      expect(frag.to_html).to eq("hello <em>world</em>")
    end

    it "raises UseAfterFreeError once the host document is freed" do
      frag = described_class.parse("<a/>", doc)
      doc.free
      expect { frag.to_html }.to raise_error(Leptris::XML::UseAfterFreeError)
    end
  end

  describe ".parse argument contract" do
    it "names the host-document contract for nil" do
      expect { described_class.parse("<a/>", nil) }
        .to raise_error(ArgumentError, /second argument must be the host/)
    end

    it "names the host-document contract for a non-Document" do
      expect { described_class.parse("<a/>", "not a document") }
        .to raise_error(ArgumentError, /second argument must be the host/)
    end
  end
end
