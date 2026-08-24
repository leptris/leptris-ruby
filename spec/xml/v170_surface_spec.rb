# frozen_string_literal: true

require "spec_helper"

RSpec.describe "v1.7.0 surface" do
  describe "batch children (leptris_node_children)" do
    let(:doc) do
      Leptris::XML.parse(%(<r>text<!--c--><![CDATA[cd]]><?pi data?><e/></r>))
    end

    it "returns every child kind in document order" do
      children = doc.root.children.to_a
      expect(children.map(&:class)).to eq([
        Leptris::XML::Text,
        Leptris::XML::Comment,
        Leptris::XML::CDATA,
        Leptris::XML::ProcessingInstruction,
        Leptris::XML::Element,
      ])
    end

    it "preserves wrapper identity across fetches" do
      expect(doc.root.children.to_a.first).to equal(doc.root.child)
    end

    it "sets parent on fetched children" do
      expect(doc.root.children.to_a.last.parent).to eq(doc.root)
    end

    it "returns an empty NodeSet for childless nodes" do
      leaf = doc.root.xpath("//e").first
      expect(leaf.children).to be_empty
      expect(leaf.children).to be_a(Leptris::XML::NodeSet)
    end

    it "memoizes children in readonly mode" do
      readonly = Leptris::XML.parse(
        %(<r>text<!--c--><![CDATA[cd]]><?pi data?><e/></r>), readonly: true)
      expect(readonly.root.children).to equal(readonly.root.children)
    end

    it "serves element_children and last_element_child off the batch" do
      expect(doc.root.element_children.map(&:name)).to eq(["e"])
      expect(doc.root.last_element_child.name).to eq("e")
    end
  end

  describe "DocumentFragment#children via the batch fetch" do
    it "returns all parsed nodes" do
      doc = Leptris::XML.parse("<r/>")
      frag = doc.fragment(%(<a/>text<b/>))
      expect(frag.children.to_a.map(&:name)).to eq(["a", "text", "b"])
    end
  end
end
