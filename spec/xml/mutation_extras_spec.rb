# frozen_string_literal: true

require "leptris/xml"

RSpec.describe "Element mutation: replace / swap / wrap / children=" do
  let(:doc) { Leptris::XML::Document.parse("<r><a/><b/><c/></r>") }
  let(:root) { doc.root }

  describe "#replace" do
    it "replaces self with a created element at the same position" do
      b = root.element_children[1]
      new_elem = doc.create_element("X")
      result = b.replace(new_elem)
      expect(result).to eq(new_elem)
      expect(root.element_children.map(&:name)).to eq(%w[a X c])
    end

    it "raises when self has no parent" do
      elem = doc.create_element("orphan")
      expect { elem.replace(doc.create_element("X")) }
        .to raise_error(Leptris::XML::Error, /no parent/)
    end
  end

  describe "#swap" do
    it "replaces self and returns self for chaining" do
      b = root.element_children[1]
      returned = b.swap(doc.create_element("X"))
      expect(returned).to eq(b)
      expect(root.element_children.map(&:name)).to eq(%w[a X c])
    end
  end

  describe "#children=" do
    it "replaces all children with the new collection" do
      root.children = [doc.create_element("p"), doc.create_element("q")]
      expect(root.element_children.map(&:name)).to eq(%w[p q])
    end

    it "clears children when given an empty array" do
      root.children = []
      expect(root.element_children).to be_empty
    end
  end

  describe "#wrap" do
    it "wraps self in a new element parsed from markup" do
      b = root.element_children[1]
      b.wrap("<div class='wrapped'/>")
      expect(root.element_children.map(&:name)).to eq(%w[a div c])
      wrapper = root.element_children[1]
      expect(wrapper["class"]).to eq("wrapped")
      expect(wrapper.element_children.map(&:name)).to eq(%w[b])
    end

    it "raises when self has no parent" do
      orphan = doc.create_element("orphan")
      expect { orphan.wrap("<x/>") }.to raise_error(Leptris::XML::Error, /no parent/)
    end
  end
end
