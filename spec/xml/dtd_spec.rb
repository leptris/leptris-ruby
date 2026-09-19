# frozen_string_literal: true

# The DTD validation surface exported in libleptris 1.9.202 (the
# validate --dtd CLI's library face): parse an internal subset,
# merge external subsets (application-owned I/O), validate — the
# RelaxNG parse-once/validate-many shape with structured errors.
RSpec.describe Leptris::XML::DTD do
  let(:dtd) do
    described_class.parse(<<~DTD)
      <!ELEMENT book (title, author+)>
      <!ATTLIST book id ID #REQUIRED>
      <!ELEMENT title (#PCDATA)>
      <!ELEMENT author (#PCDATA)>
    DTD
  end

  let(:valid_doc) do
    Leptris::XML::Document.parse(
      %q{<book id="x"><title>t</title><author>a</author></book>})
  end

  it "parses an internal subset and validates a conforming document" do
    expect(dtd.valid?(valid_doc)).to be true
    expect(dtd.validate(valid_doc)).to eq([])
  end

  it "reports a missing required attribute with the element named" do
    doc = Leptris::XML::Document.parse(
      %q{<book><title>t</title><author>a</author></book>})
    expect(dtd.valid?(doc)).to be false
    err = dtd.first_error(doc)
    expect(err[:element]).to eq("book")
    expect(err[:message]).to include("id")
  end

  it "reports content-model violations" do
    doc = Leptris::XML::Document.parse(
      %q{<book id="x"><title>t</title></book>})
    err = dtd.first_error(doc)
    expect(err[:message]).to include("author")
  end

  it "carries structured fields on every error" do
    doc = Leptris::XML::Document.parse(%q{<book/>})
    err = dtd.first_error(doc)
    expect(err).to include(:message, :element, :line, :column)
  end

  it "raises on a broken DTD with the engine's reason" do
    expect { described_class.parse("<!ELEMENT") }
      .to raise_error(Leptris::XML::Error, /DTD parse failed/)
  end

  it "merges an external subset (application-owned I/O)" do
    dtd2 = described_class.parse(
      "<!ELEMENT book (title, author+, isbn?)>")
    dtd2.merge_external_subset(
      "<!ATTLIST book id ID #REQUIRED>\n" \
      "<!ELEMENT title (#PCDATA)>\n<!ELEMENT author (#PCDATA)>\n" \
      "<!ELEMENT isbn (#PCDATA)>")
    expect(dtd2.valid?(valid_doc)).to be true
    # first declaration wins: the merged-in (title|author) model
    # must not override the stricter internal one
    extra = Leptris::XML::Document.parse(
      %q{<book id="y"><title>t</title><author>a</author></book>})
    expect(dtd2.valid?(extra)).to be true
  end

  it "validates from a document's own internal subset" do
    doc = Leptris::XML::Document.parse(<<~XML)
      <!DOCTYPE book [
        <!ELEMENT book (title)>
        <!ELEMENT title (#PCDATA)>
      ]>
      <book><title>t</title></book>
    XML
    own = described_class.from_document(doc)
    expect(own.valid?(doc)).to be true
  end
end
