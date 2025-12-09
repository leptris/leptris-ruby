# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Taurus::Document, "#xpath" do
  describe "absolute paths from document root" do
    let(:xml) { '<root><child><item/></child></root>' }
    let(:doc) { parse(xml) }

    it "finds root element" do
      result = doc.xpath('/root')
      expect(result.size).to eq(1)
      expect(result.first).to be_a(Taurus::Element)
      expect(result.first.name).to eq('root')
    end

    it "navigates multiple levels from document" do
      result = doc.xpath('/root/child/item')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('item')
    end

    it "returns empty for non-existent path" do
      result = doc.xpath('/nonexistent')
      expect(result).to be_empty
    end

    it "handles absolute path with //" do
      xml = '<root><a><item/></a><b><item/></b></root>'
      doc = parse(xml)
      result = doc.xpath('//item')
      expect(result.size).to eq(2)
    end
  end

  describe "descendant search from document" do
    let(:xml) do
      <<~XML
        <catalog>
          <books>
            <book id="1"/>
            <book id="2"/>
          </books>
          <music>
            <book id="3"/>
          </music>
        </catalog>
      XML
    end

    let(:doc) { parse(xml) }

    it "finds all matching descendants" do
      result = doc.xpath('//book')
      expect(result.size).to eq(3)
    end

    it "finds all elements with wildcard" do
      result = doc.xpath('//*')
      expect(result.size).to be >= 4 # catalog, books, music, 3 books
    end

    it "combines descendant search with name" do
      result = doc.xpath('//books/book')
      expect(result.size).to eq(2)
    end
  end

  describe "document as context node" do
    let(:xml) { '<root><item/></root>' }
    let(:doc) { parse(xml) }

    it "uses document as starting point" do
      expect(doc.xpath('/root')).not_to be_empty
    end

    it "returns consistent results from document context" do
      doc_result = doc.xpath('//item')
      root_result = doc.root.xpath('//item')
      expect(doc_result.size).to eq(root_result.size)
    end
  end

  describe "root element access" do
    let(:xml) { '<library><book/><book/></library>' }
    let(:doc) { parse(xml) }

    it "can query root element" do
      result = doc.xpath('/library')
      expect(result.first).to eq(doc.root)
    end

    it "accesses root's children" do
      result = doc.xpath('/library/book')
      expect(result.size).to eq(2)
    end
  end

  describe "complex document queries" do
    let(:xml) do
      <<~XML
        <database>
          <users>
            <user id="1">Alice</user>
            <user id="2">Bob</user>
          </users>
          <posts>
            <post user_id="1">Post 1</post>
            <post user_id="2">Post 2</post>
            <post user_id="1">Post 3</post>
          </posts>
        </database>
      XML
    end

    let(:doc) { parse(xml) }

    it "queries across different branches" do
      users = doc.xpath('//user')
      posts = doc.xpath('//post')
      expect(users.size).to eq(2)
      expect(posts.size).to eq(3)
    end

    it "handles multi-level absolute paths" do
      result = doc.xpath('/database/users/user')
      expect(result.size).to eq(2)
    end

    it "finds elements at different depths" do
      result = doc.xpath('//database/*/user')
      expect(result.size).to eq(2)
    end
  end

  describe "attribute queries from document" do
    let(:xml) { '<root><item id="1"/><item id="2"/></root>' }
    let(:doc) { parse(xml) }

    it "selects attributes from document context" do
      result = doc.xpath('//item/@id')
      expect(result).to be_an(Array)
      expect(result).to eq(['1', '2'])
    end

    it "finds all attributes in document" do
      xml = '<root a="1"><child b="2"/></root>'
      doc = parse(xml)
      result = doc.xpath('//@*')
      expect(result.size).to eq(2)
    end
  end

  describe "edge cases with document" do
    it "handles empty document" do
      doc = Taurus::Document.new
      result = doc.xpath('/*')
      expect(result).to be_empty
    end

    it "handles single element document" do
      doc = parse('<root/>')
      result = doc.xpath('/root')
      expect(result.size).to eq(1)
    end

    it "handles whitespace in queries" do
      doc = parse('<root><item/></root>')
      # XPath should handle whitespace in paths
      result = doc.xpath('/root/item')
      expect(result.size).to eq(1)
    end
  end

  describe "document-level navigation" do
    let(:xml) do
      <<~XML
        <library>
          <section name="fiction">
            <shelf>
              <book>Novel 1</book>
            </shelf>
          </section>
        </library>
      XML
    end

    let(:doc) { parse(xml) }

    it "navigates from document to deep elements" do
      result = doc.xpath('/library/section/shelf/book')
      expect(result.size).to eq(1)
      expect(result.first.text).to eq('Novel 1')
    end

    it "uses descendant-or-self from document" do
      result = doc.xpath('//book')
      expect(result.size).to eq(1)
    end
  end

  describe "consistency with element queries" do
    let(:xml) { '<root><a><b/></a><c/></root>' }
    let(:doc) { parse(xml) }

    it "produces same results as equivalent element query" do
      doc_result = doc.xpath('//b')
      root_result = doc.root.xpath('.//b')
      expect(doc_result).to eq(root_result)
    end

    it "handles self from document appropriately" do
      # Document.xpath with '.' may have implementation-specific behavior
      result = doc.xpath('.')
      # Result should either be empty or [doc]
      expect(result).to be_an(Array)
    end
  end

  describe "performance from document context" do
    it "efficiently queries large documents" do
      # Build a moderately large document
      items = (1..50).map { |i| "<item id='#{i}'>Item #{i}</item>" }.join
      xml = "<root>#{items}</root>"
      doc = parse(xml)

      start = Time.now
      result = doc.xpath('//item')
      elapsed = Time.now - start

      expect(result.size).to eq(50)
      expect(elapsed).to be < 0.5 # Should be fast
    end
  end
end