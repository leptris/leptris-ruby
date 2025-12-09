# frozen_string_literal: true

require "spec_helper"

RSpec.describe Taurus::Document do
  describe "#root caching" do
    it "caches root element on first access" do
      xml = "<root><item/></root>"
      doc = Taurus.parse(xml)
      
      # First access
      root1 = doc.root
      expect(root1.name).to eq("root")
      
      # Second access should return same object (cached)
      root2 = doc.root
      expect(root2).to be(root1)  # Same object identity
    end
    
    it "invalidates cache when root is reassigned" do
      xml = "<root><item/></root>"
      doc = Taurus.parse(xml)
      old_root = doc.root
      
      # Assign new root
      new_root = Taurus::Element.new("newroot")
      doc.root = new_root
      
      # Should return new root, not cached old one
      expect(doc.root).to be(new_root)
      expect(doc.root).not_to be(old_root)
      expect(doc.root.name).to eq("newroot")
    end
    
    it "removes old root element when assigning new one" do
      xml = "<root><item/></root>"
      doc = Taurus.parse(xml)
      old_root = doc.root
      
      # Assign new root
      new_root = Taurus::Element.new("newroot")
      doc.root = new_root
      
      # Document should only contain new root
      elements = doc.nodes.select { |n| n.is_a?(Taurus::Element) }
      expect(elements.size).to eq(1)
      expect(elements.first).to be(new_root)
      expect(elements).not_to include(old_root)
    end
    
    it "allows setting root to nil" do
      xml = "<root><item/></root>"
      doc = Taurus.parse(xml)
      
      expect(doc.root).not_to be_nil
      
      # Set root to nil
      doc.root = nil
      
      # Should have no root element
      expect(doc.root).to be_nil
      elements = doc.nodes.select { |n| n.is_a?(Taurus::Element) }
      expect(elements).to be_empty
    end
    
    it "caches nil result when no root element exists" do
      doc = Taurus::Document.new
      
      # First access - no root
      root1 = doc.root
      expect(root1).to be_nil
      
      # Second access should also be nil (cached)
      root2 = doc.root
      expect(root2).to be_nil
    end
  end
  
  describe "#root=" do
    it "sets the root element" do
      doc = Taurus::Document.new
      root = Taurus::Element.new("root")
      
      doc.root = root
      
      expect(doc.root).to eq(root)
      expect(doc.nodes).to include(root)
    end
    
    it "replaces existing root element" do
      xml = "<root><item/></root>"
      doc = Taurus.parse(xml)
      old_root = doc.root
      
      new_root = Taurus::Element.new("newroot")
      doc.root = new_root
      
      expect(doc.root).to eq(new_root)
      expect(doc.nodes).to include(new_root)
      expect(doc.nodes).not_to include(old_root)
    end
  end
  
  describe "initialization" do
    it "creates document with default prolog values" do
      doc = Taurus::Document.new
      
      expect(doc.version).to eq("1.0")
      expect(doc.encoding).to be_nil
      expect(doc.standalone).to be_nil
    end
    
    it "creates document with custom prolog values" do
      doc = Taurus::Document.new(
        version: "1.1",
        encoding: "UTF-8",
        standalone: true
      )
      
      expect(doc.version).to eq("1.1")
      expect(doc.encoding).to eq("UTF-8")
      expect(doc.standalone).to be true
    end
  end
end