# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XPath Comparison Predicates" do
  let(:xml) do
    <<~XML
      <?xml version="1.0"?>
      <inventory>
        <book id="1" price="19.99" stock="5">
          <title>Ruby Basics</title>
        </book>
        <book id="2" price="29.99" stock="3">
          <title>Advanced Ruby</title>
        </book>
        <book id="3" price="15.50" stock="10">
          <title>Learning Ruby</title>
        </book>
        <book id="4" price="29.99" stock="0">
          <title>Ruby Mastery</title>
        </book>
      </inventory>
    XML
  end

  let(:doc) { Taurus.parse(xml) }

  describe "Greater than (>)" do
    it "filters by price > 20" do
      results = doc.xpath("//book[@price > 20]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("2", "4")
    end

    it "filters by stock > 3" do
      results = doc.xpath("//book[@stock > 3]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("1", "3")
    end

    it "handles decimal comparisons" do
      results = doc.xpath("//book[@price > 19.5]")
      expect(results.size).to eq(3)
      expect(results.map { |b| b[:id] }).to contain_exactly("1", "2", "4")
    end
  end

  describe "Greater than or equal (>=)" do
    it "filters by price >= 29.99" do
      results = doc.xpath("//book[@price >= 29.99]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("2", "4")
    end

    it "filters by stock >= 5" do
      results = doc.xpath("//book[@stock >= 5]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("1", "3")
    end

    it "includes exact matches" do
      results = doc.xpath("//book[@price >= 19.99]")
      expect(results.size).to eq(3)
    end
  end

  describe "Less than (<)" do
    it "filters by price < 20" do
      results = doc.xpath("//book[@price < 20]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("1", "3")
    end

    it "filters by stock < 5" do
      results = doc.xpath("//book[@stock < 5]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("2", "4")
    end

    it "handles decimal comparisons" do
      results = doc.xpath("//book[@price < 16]")
      expect(results.size).to eq(1)
      expect(results.first[:id]).to eq("3")
    end
  end

  describe "Less than or equal (<=)" do
    it "filters by price <= 19.99" do
      results = doc.xpath("//book[@price <= 19.99]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("1", "3")
    end

    it "filters by stock <= 3" do
      results = doc.xpath("//book[@stock <= 3]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("2", "4")
    end

    it "includes exact matches" do
      results = doc.xpath("//book[@price <= 15.50]")
      expect(results.size).to eq(1)
    end
  end

  describe "Equality (=)" do
    it "filters by exact price match" do
      results = doc.xpath("//book[@price = 29.99]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("2", "4")
    end

    it "filters by exact stock match" do
      results = doc.xpath("//book[@stock = 0]")
      expect(results.size).to eq(1)
      expect(results.first[:id]).to eq("4")
    end

    it "handles string equality" do
      results = doc.xpath("//book[@id = '1']")
      expect(results.size).to eq(1)
      expect(results.first[:id]).to eq("1")
    end
  end

  describe "Inequality (!=)" do
    it "filters by price != 29.99" do
      results = doc.xpath("//book[@price != 29.99]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("1", "3")
    end

    it "filters by stock != 0" do
      results = doc.xpath("//book[@stock != 0]")
      expect(results.size).to eq(3)
      expect(results.map { |b| b[:id] }).to contain_exactly("1", "2", "3")
    end
  end

  describe "Combined predicates" do
    it "handles multiple comparison predicates" do
      results = doc.xpath("//book[@price > 15 and @price < 25]")
      expect(results.size).to eq(2)
      expect(results.map { |b| b[:id] }).to contain_exactly("1", "3")
    end

    it "handles comparison with position predicate" do
      results = doc.xpath("//book[@price > 20][1]")
      expect(results.size).to eq(1)
      expect(results.first[:id]).to eq("2")
    end

    it "handles OR conditions" do
      results = doc.xpath("//book[@price < 16 or @price > 28]")
      expect(results.size).to eq(3)
      expect(results.map { |b| b[:id] }).to contain_exactly("2", "3", "4")
    end
  end

  describe "Edge cases" do
    it "handles zero comparisons" do
      results = doc.xpath("//book[@stock = 0]")
      expect(results.size).to eq(1)
      expect(results.first[:id]).to eq("4")
    end

    it "handles empty results" do
      results = doc.xpath("//book[@price > 100]")
      expect(results).to be_empty
    end

    it "handles comparison with non-numeric values gracefully" do
      # If attribute doesn't exist or isn't numeric, should convert to NaN
      # and comparisons with NaN are always false
      results = doc.xpath("//book[@nonexistent > 5]")
      expect(results).to be_empty
    end
  end

  describe "Type coercion" do
    it "converts string attributes to numbers for comparison" do
      results = doc.xpath("//book[@price > 20]")
      expect(results.size).to eq(2)
    end

    it "handles integer comparisons" do
      results = doc.xpath("//book[@stock > 3]")
      expect(results.size).to eq(2)
    end

    it "handles float comparisons" do
      results = doc.xpath("//book[@price > 19.5]")
      expect(results.size).to eq(3)
    end
  end
end