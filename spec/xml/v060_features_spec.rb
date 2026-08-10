# frozen_string_literal: true

require "taurus/xml"

RSpec.describe "v0.6.0+ element/document deep copy + node path + fragment + doctype" do
  describe "Element#dup / Node#dup" do
    let(:doc) { Taurus::XML::Document.parse("<r><a x='1'><b>text</b></a><c/></r>") }

    it "creates a detached deep copy of an element subtree" do
      a = doc.root.first_element_child
      copy = a.dup
      expect(copy).to be_a(Taurus::XML::Element)
      expect(copy["x"]).to eq("1")
      expect(copy.element_children.map(&:name)).to eq(%w[b])
      expect(copy.content).to eq("text")
    end

    it "produces a copy whose pointer differs from the original" do
      a = doc.root.first_element_child
      copy = a.dup
      expect(copy.c_ptr).not_to eq(a.c_ptr)
    end

    it "modifications to the copy do not affect the original" do
      a = doc.root.first_element_child
      copy = a.dup
      copy["x"] = "modified"
      expect(a["x"]).to eq("1")
      expect(copy["x"]).to eq("modified")
    end

    it "can be appended to the same document as a new subtree" do
      a = doc.root.first_element_child
      copy = a.dup
      doc.root.add_child(copy)
      expect(doc.root.element_children.map(&:name)).to eq(%w[a c a])
    end

    it "alias #clone works the same" do
      a = doc.root.first_element_child
      expect(a.clone.content).to eq(a.content)
    end
  end

  describe "Document#dup / #clone" do
    it "produces a deep copy of the whole document" do
      doc = Taurus::XML::Document.parse("<r><a/></r>")
      copy = doc.dup
      expect(copy).to be_a(Taurus::XML::Document)
      expect(copy.c_ptr).not_to eq(doc.c_ptr)
      expect(copy.root.element_children.map(&:name)).to eq(%w[a])
    end

    it "mutations in the copy do not affect the original" do
      doc = Taurus::XML::Document.parse("<r><a/></r>")
      copy = doc.dup
      copy.root.first_element_child.name = "changed"
      expect(doc.root.first_element_child.name).to eq("a")
      expect(copy.root.first_element_child.name).to eq("changed")
    end
  end

  describe "Node#path / #css_path" do
    let(:doc) do
      Taurus::XML::Document.parse("<r><list><item/><item/><item/></list></r>")
    end

    it "returns the canonical XPath to a node" do
      items = doc.xpath("//item")
      path_of_second = items[1].path
      expect(path_of_second).to include("item[2]")
    end

    it "the root's path starts with /" do
      expect(doc.root.path).to match(%r{\A/r})
    end

    it "Node#css_path translates [N] to :nth-of-type(N)" do
      items = doc.xpath("//item")
      css_path = items[1].css_path
      expect(css_path).to include("item:nth-of-type(2)")
    end
  end

  describe "Document#fragment" do
    it "parses a fragment with multiple top-level nodes" do
      doc = Taurus::XML::Document.parse("<root/>")
      frag = doc.fragment("<a/><b/><c/>")
      expect(frag).to be_a(Taurus::XML::DocumentFragment)
      expect(frag.children.map(&:name)).to eq(%w[a b c])
    end

    it "parses mixed content (elements + text + comment)" do
      doc = Taurus::XML::Document.parse("<root/>")
      frag = doc.fragment("hello<a>x</a><!-- c -->")
      types = frag.children.map { |n| [n.class.name.split("::").last, n.respond_to?(:name) ? n.name : nil] }
      expect(types.map(&:first)).to include("Text", "Element", "Comment")
    end
  end

  describe "Element#add_child with String markup" do
    it "parses the markup and appends each top-level node" do
      doc = Taurus::XML::Document.parse("<root/>")
      result = doc.root.add_child("<a/><b/>")
      expect(result).to be_a(Taurus::XML::NodeSet)
      expect(doc.root.element_children.map(&:name)).to eq(%w[a b])
    end

    it "parses mixed-content strings" do
      doc = Taurus::XML::Document.parse("<root/>")
      doc.root.add_child("hello<a>x</a>")
      names = doc.root.children.map { |n| [n.class.name.split("::").last, n.respond_to?(:name) ? n.name : nil] }
      expect(names.map(&:first)).to include("Text", "Element")
    end
  end

  describe "Document#doctype / #internal_subset" do
    it "returns nil when the document has no DOCTYPE" do
      doc = Taurus::XML::Document.parse("<root/>")
      expect(doc.doctype).to be_nil
      expect(doc.internal_subset).to be_nil
    end

    it "exposes the DOCTYPE name (root element name)" do
      doc = Taurus::XML::Document.parse(%q{<!DOCTYPE html><html/>})
      dt = doc.doctype
      expect(dt).to be_a(Taurus::XML::DocType)
      expect(dt.name).to eq("html")
      expect(dt.root_name).to eq("html")
    end

    it "exposes PUBLIC and SYSTEM identifiers" do
      xml = <<~XML
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
        <html/>
      XML
      doc = Taurus::XML::Document.parse(xml)
      dt = doc.doctype
      expect(dt.public_id).to eq("-//W3C//DTD XHTML 1.0 Strict//EN")
      expect(dt.system_id).to eq("http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd")
    end

    it "exposes SYSTEM-only identifiers" do
      xml = %q{<!DOCTYPE config SYSTEM "config.dtd"><config/>}
      doc = Taurus::XML::Document.parse(xml)
      dt = doc.doctype
      expect(dt.public_id).to be_nil
      expect(dt.system_id).to eq("config.dtd")
    end

    it "exposes the internal subset (DTD declarations)" do
      pending "upstream libtaurus #253: DOCTYPE internal_subset not exposed"
      xml = %q{<!DOCTYPE root [<!ELEMENT root (a,b)><!ELEMENT a EMPTY><!ELEMENT b EMPTY>]><root><a/><b/></root>}
      doc = Taurus::XML::Document.parse(xml)
      dt = doc.doctype
      subset = dt.internal_subset
      expect(subset).to include("<!ELEMENT root")
      expect(subset).to include("<!ELEMENT a")
    end

    it "renders the full DOCTYPE declaration via #to_s" do
      xml = %q{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"><html/>}
      doc = Taurus::XML::Document.parse(xml)
      expect(doc.doctype.to_s)
        .to include('PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"')
      expect(doc.doctype.to_s).to include("<!DOCTYPE html")
    end
  end
end
