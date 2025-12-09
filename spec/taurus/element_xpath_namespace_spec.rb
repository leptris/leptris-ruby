# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Taurus::Element, '#xpath with namespace prefixes (v0.8.0)' do
  describe 'Basic namespace prefix support' do
    let(:xml) do
      <<~XML
        <root xmlns:book="http://books.org"
              xmlns:author="http://authors.org">
          <book:title>XPath Guide</book:title>
          <book:isbn>123-456</book:isbn>
          <author:name>John Doe</author:name>
          <author:email>john@example.com</author:email>
        </root>
      XML
    end

    let(:doc) { parse(xml) }

    it 'finds elements by namespace prefix' do
      result = doc.xpath('//book:title')
      expect(result.size).to eq(1)
      expect(result[0].text).to eq('XPath Guide')
    end

    it 'distinguishes between same local names in different namespaces' do
      # Both have 'title' as local name but different namespaces
      xml_multi = <<~XML
        <root xmlns:book="http://books.org"
              xmlns:article="http://articles.org">
          <book:title>Book Title</book:title>
          <article:title>Article Title</article:title>
        </root>
      XML
      
      doc_multi = parse(xml_multi)
      
      book_titles = doc_multi.xpath('//book:title')
      article_titles = doc_multi.xpath('//article:title')
      
      expect(book_titles.size).to eq(1)
      expect(article_titles.size).to eq(1)
      expect(book_titles[0].text).to eq('Book Title')
      expect(article_titles[0].text).to eq('Article Title')
    end

    it 'supports multiple elements with same prefix' do
      result = doc.xpath('//book:*')
      expect(result.size).to eq(2)
      expect(result.map(&:text).sort).to eq(['123-456', 'XPath Guide'])
    end

    it 'supports wildcard with namespace prefix' do
      author_elements = doc.xpath('//author:*')
      expect(author_elements.size).to eq(2)
      expect(author_elements[0].text).to eq('John Doe')
      expect(author_elements[1].text).to eq('john@example.com')
    end
  end

  describe 'Namespace prefixes in predicates' do
    let(:xml) do
      <<~XML
        <root xmlns:book="http://books.org">
          <section>
            <book:title>First Book</book:title>
            <description>Book description</description>
          </section>
          <section>
            <description>No book here</description>
          </section>
        </root>
      XML
    end

    let(:doc) { parse(xml) }

    it 'works in predicates' do
      result = doc.xpath('//section[book:title]')
      expect(result.size).to eq(1)
      expect(result[0].xpath('.//book:title')[0].text).to eq('First Book')
    end

    it 'combines prefix with attribute predicates' do
      xml_with_attrs = <<~XML
        <root xmlns:book="http://books.org">
          <book:item id="1">First</book:item>
          <book:item id="2">Second</book:item>
          <book:item>Third</book:item>
        </root>
      XML
      
      doc_attrs = parse(xml_with_attrs)
      result = doc_attrs.xpath('//book:item[@id]')
      expect(result.size).to eq(2)
    end
  end

  describe 'Nested namespaces' do
    let(:xml) do
      <<~XML
        <root xmlns:outer="http://outer.org">
          <outer:container xmlns:inner="http://inner.org">
            <inner:item>Item 1</inner:item>
            <outer:item>Item 2</outer:item>
          </outer:container>
        </root>
      XML
    end

    let(:doc) { parse(xml) }

    it 'handles nested namespace declarations' do
      inner_items = doc.xpath('//inner:item')
      outer_items = doc.xpath('//outer:item')
      
      expect(inner_items.size).to eq(1)
      expect(outer_items.size).to eq(1)
      expect(inner_items[0].text).to eq('Item 1')
      expect(outer_items[0].text).to eq('Item 2')
    end

    it 'finds all items regardless of namespace' do
      # Without prefix, should match local name only
      all_items = doc.xpath('//item')
      expect(all_items.size).to eq(2)
    end
  end

  describe 'Default namespace' do
    let(:xml) do
      <<~XML
        <root xmlns="http://default.org"
              xmlns:special="http://special.org">
          <item>Default NS Item</item>
          <special:item>Special NS Item</special:item>
        </root>
      XML
    end

    let(:doc) { parse(xml) }

    it 'matches elements without prefix using local name' do
      # Elements in default namespace should match by local name
      items = doc.xpath('//item')
      expect(items.size).to eq(2)
    end

    it 'matches prefixed elements explicitly' do
      special_items = doc.xpath('//special:item')
      expect(special_items.size).to eq(1)
      expect(special_items[0].text).to eq('Special NS Item')
    end
  end

  describe 'Complex queries with namespaces' do
    let(:xml) do
      <<~XML
        <catalog xmlns:book="http://books.org"
                 xmlns:magazine="http://magazines.org">
          <book:publication year="2020">
            <book:title>Learning XPath</book:title>
            <book:author>Jane Smith</book:author>
          </book:publication>
          <magazine:publication year="2021">
            <magazine:title>Tech Weekly</magazine:title>
            <magazine:editor>Bob Johnson</magazine:editor>
          </magazine:publication>
          <book:publication year="2022">
            <book:title>Advanced XPath</book:title>
            <book:author>Jane Smith</book:author>
          </book:publication>
        </catalog>
      XML
    end

    let(:doc) { parse(xml) }

    it 'combines namespace prefix with attribute filters' do
      result = doc.xpath('//book:publication[@year="2020"]')
      expect(result.size).to eq(1)
      expect(result[0].xpath('.//book:title')[0].text).to eq('Learning XPath')
    end

    it 'finds all publications regardless of namespace' do
      all_pubs = doc.xpath('//publication')
      expect(all_pubs.size).to eq(3)
    end

    it 'chains namespace-aware queries' do
      # Find book publications, then their titles
      book_titles = doc.xpath('//book:publication/book:title')
      expect(book_titles.size).to eq(2)
      expect(book_titles.map(&:text).sort).to eq(['Advanced XPath', 'Learning XPath'])
    end

    it 'uses position predicates with namespace prefixes' do
      first_book = doc.xpath('//book:publication[1]')
      expect(first_book.size).to eq(1)
      expect(first_book[0][:year]).to eq('2020')
    end

    it 'combines wildcards with namespace prefixes' do
      # All children of book:publication elements
      book_children = doc.xpath('//book:publication/book:*')
      expect(book_children.size).to eq(4)  # 2 publications × (title + author)
    end
  end

  describe 'Descendant axis with namespaces' do
    let(:xml) do
      <<~XML
        <root xmlns:ns="http://example.org">
          <ns:level1>
            <ns:level2>
              <ns:target>Found It!</ns:target>
            </ns:level2>
          </ns:level1>
        </root>
      XML
    end

    let(:doc) { parse(xml) }

    it 'finds descendants with namespace prefix' do
      result = doc.xpath('//ns:target')
      expect(result.size).to eq(1)
      expect(result[0].text).to eq('Found It!')
    end

    it 'finds all descendants regardless of namespace' do
      all_targets = doc.xpath('//target')
      expect(all_targets.size).to eq(1)
    end
  end

  describe 'Multiple namespace prefixes on same element' do
    let(:xml) do
      <<~XML
        <root xmlns:a="http://a.org"
              xmlns:b="http://b.org"
              xmlns:c="http://c.org">
          <a:item>Item A</a:item>
          <b:item>Item B</b:item>
          <c:item>Item C</c:item>
          <item>No namespace</item>
        </root>
      XML
    end

    let(:doc) { parse(xml) }

    it 'distinguishes elements with different namespace prefixes' do
      a_items = doc.xpath('//a:item')
      b_items = doc.xpath('//b:item')
      c_items = doc.xpath('//c:item')
      
      expect(a_items.size).to eq(1)
      expect(b_items.size).to eq(1)
      expect(c_items.size).to eq(1)
      
      expect(a_items[0].text).to eq('Item A')
      expect(b_items[0].text).to eq('Item B')
      expect(c_items[0].text).to eq('Item C')
    end

    it 'finds items without prefix using local name' do
      no_prefix = doc.xpath('//item')
      expect(no_prefix.size).to eq(4)  # All items including namespaced ones
    end
  end

  describe 'Backward compatibility' do
    let(:xml) do
      <<~XML
        <root>
          <item>Plain Item 1</item>
          <item>Plain Item 2</item>
        </root>
      XML
    end

    let(:doc) { parse(xml) }

    it 'works without namespaces (backward compatible)' do
      items = doc.xpath('//item')
      expect(items.size).to eq(2)
    end

    it 'matches local names when no namespace is used' do
      result = doc.xpath('//item[1]')
      expect(result.size).to eq(1)
      expect(result[0].text).to eq('Plain Item 1')
    end
  end
end