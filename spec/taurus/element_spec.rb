# frozen_string_literal: true

require "spec_helper"

RSpec.describe Taurus::Element do
  describe "parent manipulation" do
    it "sets parent correctly" do
      parent = Taurus::Element.new("parent")
      child = Taurus::Element.new("child")

      child.parent = parent

      expect(child.parent).to eq(parent)
    end

    it "prevents circular references" do
      elem1 = Taurus::Element.new("elem1")
      elem2 = Taurus::Element.new("elem2")
      elem3 = Taurus::Element.new("elem3")

      elem1.parent = elem2
      elem2.parent = elem3

      # This should not create a circular reference
      original_parent = elem3.parent
      elem3.parent = elem1

      expect(elem3.parent).to eq(original_parent)  # Parent should not change
    end

    it "allows setting parent to nil" do
      parent = Taurus::Element.new("parent")
      child = Taurus::Element.new("child")

      child.parent = parent
      expect(child.parent).to eq(parent)

      child.parent = nil
      expect(child.parent).to be_nil
    end
  end

  describe "node manipulation" do
    it "adds child elements" do
      parent = Taurus::Element.new("parent")
      child = Taurus::Element.new("child")

      parent << child

      expect(parent.nodes).to include(child)
      expect(child.parent).to eq(parent)
    end

    it "removes elements from parent" do
      parent = Taurus::Element.new("parent")
      child = Taurus::Element.new("child")

      parent << child
      expect(parent.nodes).to include(child)
      expect(child.parent).to eq(parent)

      child.remove
      expect(parent.nodes).not_to include(child)
      expect(child.parent).to be_nil
    end

    it "adds child with add_child method" do
      parent = Taurus::Element.new("parent")
      child = Taurus::Element.new("child")

      parent.add_child(child)

      expect(parent.nodes).to include(child)
      expect(child.parent).to eq(parent)
    end

    it "removes child from old parent when adding to new parent" do
      old_parent = Taurus::Element.new("old_parent")
      new_parent = Taurus::Element.new("new_parent")
      child = Taurus::Element.new("child")

      old_parent.add_child(child)
      expect(old_parent.nodes).to include(child)
      expect(child.parent).to eq(old_parent)

      new_parent.add_child(child)
      expect(old_parent.nodes).not_to include(child)
      expect(new_parent.nodes).to include(child)
      expect(child.parent).to eq(new_parent)
    end
  end

  describe "text content" do
    it "returns text content" do
      elem = Taurus::Element.new("test")
      elem << "Hello World"

      expect(elem.text).to eq("Hello World")
    end

    it "returns nil when no text content" do
      elem = Taurus::Element.new("test")

      expect(elem.text).to be_nil
    end

    it "replaces text content" do
      elem = Taurus::Element.new("test")
      elem << "Old text"
      elem << Taurus::Element.new("child")

      elem.replace_text("New text")

      expect(elem.nodes).to eq(["New text"])
      expect(elem.text).to eq("New text")
    end
  end

  describe "attributes" do
    it "sets and gets attributes" do
      elem = Taurus::Element.new("test")

      elem["name"] = "value"
      expect(elem["name"]).to eq("value")
    end

    it "supports symbol keys" do
      elem = Taurus::Element.new("test")

      elem[:name] = "value"
      expect(elem[:name]).to eq("value")
      expect(elem["name"]).to eq("value")
    end
  end

  describe "equality" do
    it "compares equal elements" do
      elem1 = Taurus::Element.new("test")
      elem2 = Taurus::Element.new("test")

      expect(elem1).to eq(elem2)
    end

    it "compares different elements" do
      elem1 = Taurus::Element.new("test1")
      elem2 = Taurus::Element.new("test2")

      expect(elem1).not_to eq(elem2)
    end
  end

  describe "element name interning (Session 72 optimization)" do
    it "returns interned (frozen) strings for parsed element names" do
      xml = "<root><item/><item/></root>"
      doc = Taurus.parse(xml)

      name1 = doc.root.nodes[0].name
      name2 = doc.root.nodes[1].name

      # Names should be frozen (interned)
      expect(name1).to be_frozen
      expect(name2).to be_frozen

      # Same element names should be same object (interned)
      expect(name1.object_id).to eq(name2.object_id)
    end

    it "interned names work with string comparison" do
      xml = "<root><item/></root>"
      doc = Taurus.parse(xml)

      expect(doc.root.name).to eq("root")
      expect(doc.root.nodes.first.name).to eq("item")
    end

    it "different element names are different objects" do
      xml = "<root><item/><other/></root>"
      doc = Taurus.parse(xml)

      name1 = doc.root.nodes[0].name
      name2 = doc.root.nodes[1].name

      expect(name1).to eq("item")
      expect(name2).to eq("other")
      expect(name1.object_id).not_to eq(name2.object_id)
    end

    it "root element name is also interned" do
      xml = "<root><root/></root>"
      doc = Taurus.parse(xml)

      root_name = doc.root.name
      child_name = doc.root.nodes.first.name

      expect(root_name).to be_frozen
      expect(child_name).to be_frozen
      expect(root_name.object_id).to eq(child_name.object_id)
    end

  describe "attribute access optimization (Session 73)" do
    let(:elem) do
      Taurus::Element.new("test").tap do |e|
        e[:name] = "value"
        e[:count] = "42"
        e[:enabled] = "true"
      end
    end

    it "symbol access uses fast-path (no conversion)" do
      # Fast path: symbol → direct lookup
      expect(elem[:name]).to eq("value")
      expect(elem[:count]).to eq("42")
      expect(elem[:enabled]).to eq("true")
    end

    it "string access still works (backwards compatible)" do
      # Slow path: string → convert to symbol
      expect(elem["name"]).to eq("value")
      expect(elem["count"]).to eq("42")
      expect(elem["enabled"]).to eq("true")
    end

    it "mixed access works correctly" do
      elem[:fast] = "symbol"
      elem["slow"] = "string"
      
      expect(elem[:fast]).to eq("symbol")
      expect(elem["slow"]).to eq("string")
      expect(elem[:slow]).to eq("string")  # Symbol access to string-set attr
      expect(elem["fast"]).to eq("symbol")  # String access to symbol-set attr
    end

    it "nil for missing attributes (both paths)" do
      expect(elem[:missing]).to be_nil
      expect(elem["missing"]).to be_nil
    end

    it "handles parsed document attributes with symbol fast-path" do
      xml = '<root><item id="123" name="test"/></root>'
      doc = Taurus.parse(xml)
      item = doc.root.nodes.first
      
      # Should use fast-path for symbol access
      expect(item[:id]).to eq("123")
      expect(item[:name]).to eq("test")
      
      # String access should still work
      expect(item["id"]).to eq("123")
      expect(item["name"]).to eq("test")
    end

    it "multiple attribute reads use fast-path consistently" do
      # This tests that multiple reads benefit from fast-path
      10.times do
        expect(elem[:name]).to eq("value")
        expect(elem[:count]).to eq("42")
      end
    end
  end

  describe "children access optimization (Session 74)" do
    it "nodes array is initialized in Ruby constructor" do
      elem = Taurus::Element.new("test")
      
      # @nodes should be initialized immediately (not lazy)
      expect(elem.nodes).to be_an(Array)
      expect(elem.nodes).to be_empty
    end

    it "nodes array is initialized in C parser" do
      xml = "<root><item/></root>"
      doc = Taurus.parse(xml)
      
      # @nodes should be initialized by C create_element
      expect(doc.root.nodes).to be_an(Array)
      expect(doc.root.nodes.size).to eq(1)
    end

    it "nodes array works with direct access (no lazy init)" do
      elem = Taurus::Element.new("test")
      child1 = Taurus::Element.new("child1")
      child2 = Taurus::Element.new("child2")
      
      elem << child1
      elem << child2
      
      # Multiple reads should work without lazy check
      expect(elem.nodes.size).to eq(2)
      expect(elem.nodes.size).to eq(2)
      expect(elem.nodes).to include(child1, child2)
    end

    it "empty element has empty nodes array (not nil)" do
      elem = Taurus::Element.new("test")
      
      # Should return empty array, not nil
      expect(elem.nodes).not_to be_nil
      expect(elem.nodes).to eq([])
    end

    it "parsed empty element has empty nodes array" do
      xml = "<root><empty/></root>"
      doc = Taurus.parse(xml)
      empty = doc.root.nodes.first
      
      # Even empty elements should have initialized @nodes
      expect(empty.nodes).to be_an(Array)
      expect(empty.nodes).to be_empty
    end

    it "nodes array identity is consistent (same object)" do
      elem = Taurus::Element.new("test")
      
      # Should return same array object every time (direct access)
      array1 = elem.nodes
      array2 = elem.nodes
      
      expect(array1.object_id).to eq(array2.object_id)
    end
  end
  end
end