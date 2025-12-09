# frozen_string_literal: true

require "spec_helper"

RSpec.describe Taurus::Adapter::Taurus do
  let(:adapter) { described_class }
  let(:xml) do
    <<~XML
      <root>
        <book price="10">
          <title>Book 1</title>
          <author>Author A</author>
        </book>
        <book price="20">
          <title>Book 2</title>
          <author>Author B</author>
        </book>
      </root>
    XML
  end

  describe ".parse" do
    it "parses XML using Taurus" do
      doc = adapter.parse(xml)

      expect(doc).to be_a(Taurus::Document)
      expect(doc.root.name).to eq("root")
    end
  end

  describe ".xpath" do
    let(:doc) { adapter.parse(xml) }

    it "executes simple XPath queries" do
      # Taurus has complete XPath 1.0 support through C extension
      result = adapter.xpath(doc.root, "book")

      expect(result).to be_a(Taurus::NodeSet)
      expect(result.size).to eq(2)
    end
  end

  describe ".at_xpath" do
    let(:doc) { adapter.parse(xml) }

    it "returns first matching node" do
      result = adapter.at_xpath(doc.root, "book")

      expect(result).to be_a(Taurus::Element)
      expect(result.name).to eq("book")
    end
  end

  describe ".xpath_supported?" do
    it "returns true" do
      expect(adapter.xpath_supported?).to be true
    end
  end

  describe ".capabilities" do
    it "reports basic capabilities" do
      caps = adapter.capabilities

      expect(caps[:parse]).to be true
      expect(caps[:namespace_aware]).to be true
      expect(caps[:xpath_support]).to eq(:full)  # Full XPath 1.0!
      expect(caps[:xpath_full]).to be true
      expect(caps[:xpath_functions]).to eq(:complete)  # All 27 functions!
    end
  end
end
