# frozen_string_literal: true

require "leptris/xml"

RSpec.describe "Leptris::XML Searchable via XPath" do
  let(:doc) do
    Leptris::XML::Document.parse(<<~XML)
      <library version="2.0">
        <book id="1"><title>Ruby</title></book>
        <book id="2"><title>XML</title></book>
        <book id="3"><title>XPath</title></book>
      </library>
    XML
  end

  it "evaluates count() and returns a Float" do
    expect(doc.xpath("count(//book)")).to eq(3.0)
  end

  it "returns a NodeSet for //element queries" do
    books = doc.xpath("//book")
    expect(books).to be_a(Leptris::XML::NodeSet)
    expect(books.length).to eq(3)
  end

  it "returns a String for string() queries" do
    title = doc.xpath("string(//book[@id='1']/title)")
    expect(title).to eq("Ruby")
  end

  it "returns a Boolean for predicate-only queries" do
    # Uses boolean() which libleptris v0.5.5+ flat XPath dispatcher
    # correctly supports.
    expect(doc.xpath("boolean(//book)")).to be true
    expect(doc.xpath("boolean(//missing)")).to be false
  end

  # Regression for upstream libleptris #201 (fixed in v0.5.7): the v0.5.5
  # flat XPath dispatcher over-matched expressions starting with count(...),
  # returning the inner number rather than evaluating the full comparison.
  it "returns a Boolean for count(...) > N expressions" do
    expect(doc.xpath("count(//book) > 0")).to be true
    expect(doc.xpath("count(//missing) > 0")).to be false
    expect(doc.xpath("count(//book) > 5")).to be false
    expect(doc.xpath("count(//book) >= 3")).to be true
  end

  it "supports at_xpath returning the first match" do
    first_book = doc.at_xpath("//book")
    expect(first_book["id"]).to eq("1")
  end

  it "supports xpath on Element receiver (context-relative)" do
    second_book = doc.at_xpath("//book[@id='2']")
    title = second_book.xpath("title")
    expect(title).to be_a(Leptris::XML::NodeSet)
    expect(title.first.content).to eq("XML")
  end

  it "supports . at context node" do
    first_book = doc.at_xpath("//book")
    expect(first_book.xpath(".")).to be_a(Leptris::XML::NodeSet)
  end

  it "supports XPath on NodeSet (search each member)" do
    books = doc.xpath("//book")
    all_titles = books.xpath("title")
    expect(all_titles.length).to eq(3)
    expect(all_titles.map(&:content)).to eq(%w[Ruby XML XPath])
  end
end

RSpec.describe "upstream #630: relative namespaced descendant paths" do
  it "evaluates .//ns:x and descendant::ns:x from element context" do
    doc = Leptris::XML::Document.parse(
      %q{<r xmlns:x="urn:x"><a><x:b id="1"/></a><x:b id="2"/></r>})
    a = doc.root.element_children.first
    ns = { "x" => "urn:x" }
    expect(a.xpath(".//x:b", ns).map { |e| e["id"] }).to eq(%w[1])
    expect(a.xpath("descendant::x:b", ns).map { |e| e["id"] }).to eq(%w[1])
    expect(doc.xpath("//x:b", ns).map { |e| e["id"] }).to eq(%w[1 2])
  end
end
