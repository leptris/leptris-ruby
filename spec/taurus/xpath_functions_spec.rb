# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "XPath Functions" do
  describe "last() function" do
    it "returns the last element in a nodeset" do
      xml = '<root><a/><b/><c/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[last()]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('c')
    end

    it "works with position comparison" do
      xml = '<root><a/><b/><c/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[position() = last()]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('c')
    end

    it "works in complex paths" do
      xml = '<root><section><item/><item/><item/></section></root>'
      doc = parse(xml)
      result = doc.root.xpath('section/item[last()]')
      expect(result.size).to eq(1)
    end

    it "works with descendant axis" do
      xml = '<root><a/><b/><c/></root>'
      doc = parse(xml)
      result = doc.root.xpath('descendant::*[last()]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('c')
    end

    it "works with different node counts" do
      xml = '<root><item/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[last()]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('item')
    end

    it "works with empty nodeset" do
      xml = '<root/>'
      doc = parse(xml)
      result = doc.root.xpath('*[last()]')
      expect(result).to be_empty
    end

    it "can be used in arithmetic expressions" do
      xml = '<root><a/><b/><c/><d/></root>'
      doc = parse(xml)
      # last() - 1 should select the 3rd element (c)
      result = doc.root.xpath('*[position() = last() - 1]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('c')
    end

    it "works with multiple predicates" do
      xml = '<root><item id="1"/><item id="2"/><item id="3"/></root>'
      doc = parse(xml)
      result = doc.root.xpath('item[@id][last()]')
      expect(result.size).to eq(1)
      expect(result.first[:id]).to eq('3')
    end
  end

  describe "position() function" do
    it "returns the position of each node" do
      xml = '<root><a/><b/><c/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[position() = 1]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('a')
    end

    it "works with position 2" do
      xml = '<root><a/><b/><c/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[position() = 2]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('b')
    end

    it "works with position 3" do
      xml = '<root><a/><b/><c/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[position() = 3]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('c')
    end

    it "can be compared with last()" do
      xml = '<root><a/><b/><c/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[position() = last()]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('c')
    end

    it "works with greater than operator" do
      xml = '<root><a/><b/><c/><d/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[position() > 2]')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to eq(['c', 'd'])
    end

    it "works with less than operator" do
      xml = '<root><a/><b/><c/><d/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[position() < 3]')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to eq(['a', 'b'])
    end

    it "works with arithmetic" do
      xml = '<root><a/><b/><c/><d/></root>'
      doc = parse(xml)
      # position() + 1 = 3 means position 2
      result = doc.root.xpath('*[position() + 1 = 3]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('b')
    end

    it "works in complex paths" do
      xml = '<root><section><item/><item/><item/></section></root>'
      doc = parse(xml)
      result = doc.root.xpath('section/item[position() = 2]')
      expect(result.size).to eq(1)
    end

    it "works with descendant axis" do
      xml = '<root><section><a/><b/><c/></section></root>'
      doc = parse(xml)
      # descendant::* gives [section, a, b, c], position 2 is 'a'
      result = doc.root.xpath('descendant::*[position() = 2]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('a')
    end

    it "returns empty for out of range position" do
      xml = '<root><a/><b/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[position() = 10]')
      expect(result).to be_empty
    end
  end

  describe "function call error handling" do
    it "handles unknown function gracefully" do
      xml = '<root><a/></root>'
      doc = parse(xml)
      expect {
        doc.root.xpath('*[unknown-function()]')
      }.to raise_error(RuntimeError, /Unknown function/)
    end

    it "validates argument count for last()" do
      xml = '<root><a/></root>'
      doc = parse(xml)
      # last() takes no arguments, this should fail at evaluation
      # Note: This might be caught by parser first
      expect {
        doc.root.xpath('*[last(1)]')
      }.to raise_error(RuntimeError)
    end

    it "validates argument count for position()" do
      xml = '<root><a/></root>'
      doc = parse(xml)
      expect {
        doc.root.xpath('*[position(1)]')
      }.to raise_error(RuntimeError)
    end
  end
end