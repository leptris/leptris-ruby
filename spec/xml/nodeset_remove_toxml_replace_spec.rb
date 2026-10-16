# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#455 / #456 / #457 — nokogiri parity for the three
# NodeSet/Element faces the vectory migration relies on.
RSpec.describe "NodeSet#remove / NodeSet#to_xml / Element#replace markup" do
  describe "NodeSet#remove (leptris-ruby#455)" do
    let(:doc) { Leptris::XML.parse("<r><a/><b/></r>") }

    it "unlinks every member from the tree" do
      doc.xpath(".//a").remove
      expect(doc.xpath(".//a").empty?).to be(true)
      expect(doc.root.children.map(&:name)).to eq(["b"])
    end

    it "is aliased as unlink" do
      doc.xpath(".//b").unlink
      expect(doc.root.children.map(&:name)).to eq(["a"])
    end

    it "returns the nodeset for chaining" do
      expect(doc.xpath(".//a").remove).to be_a(Leptris::XML::NodeSet)
    end
  end

  describe "NodeSet#to_xml (leptris-ruby#456)" do
    let(:doc) { Leptris::XML.parse("<r><a>x</a><b>y</b></r>") }

    it "concatenates member serialization in order" do
      expect(doc.root.children.to_xml).to eq("<a>x</a><b>y</b>")
    end

    it "serializes element members with attributes" do
      doc2 = Leptris::XML.parse('<r><a id="1"/><b id="2"/></r>')
      expect(doc2.root.children.to_xml).to eq('<a id="1"/><b id="2"/>')
    end

    it "serializes text members too" do
      doc2 = Leptris::XML.parse("<r>t<a/></r>")
      expect(doc2.root.children.to_xml).to eq("t<a/>")
    end
  end

  describe "Element#replace with markup String (leptris-ruby#457)" do
    let(:doc) { Leptris::XML.parse("<r><a/></r>") }

    it "parses markup in document context and splices it in" do
      doc.xpath("//a").first.replace("<c/>")
      expect(doc.root.children.map(&:name)).to eq(["c"])
    end

    it "returns the replacement node" do
      new_node = doc.xpath("//a").first.replace("<c/>")
      expect(new_node).to be_a(Leptris::XML::Element)
      expect(new_node.name).to eq("c")
    end

    it "accepts markup with attributes and text" do
      doc2 = Leptris::XML.parse("<r><a/></r>")
      doc2.at_xpath("//a").replace('<c id="1">hi</c>')
      expect(doc2.root.children.to_xml).to eq('<c id="1">hi</c>')
    end

    it "still accepts a node argument" do
      doc2 = Leptris::XML.parse("<r><a/><b/></r>")
      replacement = doc2.create_element("c")
      doc2.at_xpath("//a").replace(replacement)
      expect(doc2.root.children.map(&:name)).to eq(["c", "b"])
    end
  end
end

RSpec.describe "Element#replace with a DocumentFragment (ruby#457 follow-up)" do
  it "splices the fragment's CHILDREN per DOM Core, not the fragment node" do
    doc = Leptris::XML.parse("<r><image/></r>")
    img = doc.root.element_children.first
    img.replace(doc.fragment('<svg id="s1"/>'))
    expect(doc.root.element_children.map(&:name)).to eq(["svg"])
    expect(doc.root.to_xml).to eq('<r><svg id="s1"/></r>')
  end

  it "splices multi-node fragments in order" do
    doc = Leptris::XML.parse("<r><image/></r>")
    img = doc.root.element_children.first
    img.replace(doc.fragment("<a/><b/>"))
    expect(doc.root.element_children.map(&:name)).to eq(["a", "b"])
  end

  it "returns a NodeSet for multi-node fragments (the #457 contract)" do
    doc = Leptris::XML.parse("<r><image/></r>")
    img = doc.root.element_children.first
    installed = img.replace(doc.fragment("<a/><b/>"))
    expect(installed).to be_a(Leptris::XML::NodeSet)
    expect(installed.map(&:name)).to eq(["a", "b"])
  end
end

RSpec.describe "replace keeps the replacement's namespace when the replaced element self-declares (ruby#480)" do
  MARKUP = '<svg xmlns="http://www.w3.org/2000/svg" ' \
           'xmlns:xlink="http://www.w3.org/1999/xlink" id="s2">' \
           '<a xlink:href="#x"><rect/></a></svg>'.freeze

  it "keeps the replacement's default xmlns through replace(markup)" do
    doc = Leptris::XML.parse(
      '<fig><svg xmlns="http://www.w3.org/2000/svg" id="s"><a xlink:href="#y"/></svg></fig>'
    )
    img = doc.at_xpath("//*[local-name()='svg']")
    img.replace(MARKUP)
    new_svg = doc.at_xpath("//*[local-name()='svg']")
    expect(new_svg.namespace&.href).to eq("http://www.w3.org/2000/svg")
    expect(doc.at_xpath("//fig").to_xml).to include("svg")
    expect(doc.at_xpath("//fig").to_xml).to include('xmlns="http://www.w3.org/2000/svg"')
  end

  it "keeps the declaration when the scopes differ (shadowing still wins)" do
    doc = Leptris::XML.parse(
      '<fig><svg xmlns="urn:old" id="s"/></fig>'
    )
    doc.at_xpath("//*[local-name()='svg']").replace(MARKUP)
    new_svg = doc.at_xpath("//*[local-name()='svg']")
    expect(new_svg.namespace&.href).to eq("http://www.w3.org/2000/svg")
  end

  it "keeps a sibling insertion's own default xmlns (no replace at all)" do
    doc = Leptris::XML.parse(
      '<fig><svg xmlns="http://www.w3.org/2000/svg" id="s"/></fig>'
    )
    old = doc.at_xpath("//*[local-name()='svg']")
    old.add_next_sibling(doc.fragment(MARKUP).children.first)
    sibs = doc.at_xpath("//fig").element_children
    expect(sibs.map { |e| e.namespace&.href })
      .to all(eq("http://www.w3.org/2000/svg"))
  end
end
