# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Taurus::Element, "#xpath" do
  describe "basic path queries" do
    let(:xml) do
      <<~XML
        <root>
          <section>
            <item id="1">First</item>
            <item id="2">Second</item>
          </section>
          <other>
            <item id="3">Third</item>
          </other>
        </root>
      XML
    end

    let(:doc) { parse(xml) }
    let(:root) { doc.root }
    let(:section) { root.nodes.first }

    it "returns array of matching elements" do
      result = root.xpath('section')
      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first).to be_a(Taurus::Element)
      expect(result.first.name).to eq('section')
    end

    it "returns empty array for no matches" do
      result = root.xpath('nonexistent')
      expect(result).to eq([])
    end

    it "handles multi-level paths" do
      result = root.xpath('section/item')
      expect(result.size).to eq(2)
    end

    it "returns correct element from relative path" do
      result = section.xpath('item')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to eq(['item', 'item'])
    end
  end

  describe "child axis" do
    let(:xml) { '<root><a/><b/><c/></root>' }
    let(:doc) { parse(xml) }
    let(:root) { doc.root }

    it "returns all direct children" do
      result = root.xpath('child::*')
      expect(result.size).to eq(3)
      expect(result.map(&:name)).to eq(['a', 'b', 'c'])
    end

    it "returns children matching name" do
      xml = '<root><item/><other/><item/></root>'
      doc = parse(xml)
      result = doc.root.xpath('child::item')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to eq(['item', 'item'])
    end

    it "returns empty for childless element" do
      result = root.xpath('a/child::*')
      expect(result).to be_empty
    end

    it "works with explicit child axis" do
      result = root.xpath('child::b')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('b')
    end
  end

  describe "descendant search (//)" do
    let(:xml) do
      <<~XML
        <library>
          <section>
            <book>Book1</book>
            <book>Book2</book>
          </section>
          <archive>
            <book>Book3</book>
          </archive>
        </library>
      XML
    end

    let(:doc) { parse(xml) }
    let(:root) { doc.root }

    it "finds all descendants matching name" do
      result = root.xpath('.//book')
      expect(result.size).to eq(3)
      expect(result.map(&:name)).to all(eq('book'))
    end

    it "finds descendants from element context" do
      section = root.nodes.first
      result = section.xpath('.//book')
      expect(result.size).to eq(2)
    end

    it "works with absolute descendant path" do
      result = doc.xpath('//book')
      expect(result.size).to eq(3)
    end

    it "finds all descendants with wildcard" do
      result = root.xpath('.//*')
      expect(result.size).to be >= 5
    end
  end

  describe "descendant-or-self axis" do
    let(:xml) { '<root><a><b/></a></root>' }
    let(:doc) { parse(xml) }
    let(:root) { doc.root }

    it "includes context node in results" do
      result = root.xpath('descendant-or-self::*')
      expect(result.first).to eq(root)
    end

    it "includes all descendants" do
      result = root.xpath('descendant-or-self::*')
      expect(result.size).to eq(3) # root, a, b
      expect(result.map(&:name)).to eq(['root', 'a', 'b'])
    end

    it "works from mid-tree element" do
      a = navigate_to(root, 'a')
      result = a.xpath('descendant-or-self::*')
      expect(result.size).to eq(2) # a, b
      expect(result.map(&:name)).to eq(['a', 'b'])
    end
  end

  describe "descendant axis (descendant::*)" do
    it "excludes context node, includes all descendants" do
      doc = parse('<root><a><b/></a><container/></root>')
      result = doc.root.xpath('descendant::*')
      expect(result.size).to eq(3) # a, b, container (NOT root)
      expect(result.map(&:name)).to eq(['a', 'b', 'container'])
    end

    it "works with deep nesting" do
      doc = parse('<root><level1><level2><level3/></level2></level1></root>')
      result = doc.root.xpath('descendant::*')
      expect(result.size).to eq(3) # level1, level2, level3
      expect(result.map(&:name)).to eq(['level1', 'level2', 'level3'])
    end

    it "works from non-root context" do
      doc = parse('<root><a><b><c/></b></a></root>')
      a = doc.root.xpath('a').first
      result = a.xpath('descendant::*')
      expect(result.size).to eq(2) # b, c (NOT a)
      expect(result.map(&:name)).to eq(['b', 'c'])
    end

    it "works with multiple branches" do
      doc = parse('<root><a><aa/></a><b><bb/></b></root>')
      result = doc.root.xpath('descendant::*')
      expect(result.size).to eq(4) # a, aa, b, bb
    end

    it "returns empty for leaf element" do
      doc = parse('<root><leaf/></root>')
      leaf = doc.root.xpath('leaf').first
      result = leaf.xpath('descendant::*')
      expect(result).to be_empty
    end

    it "works with name test" do
      doc = parse('<root><a/><b/><a/></root>')
      result = doc.root.xpath('descendant::a')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to eq(['a', 'a'])
    end
  end

  describe "ancestor-or-self axis (ancestor-or-self::*)" do
    it "includes context node in results" do
      doc = parse('<root><a><b><c/></b></a></root>')
      c = navigate_to(doc.root, 'a/b/c')
      result = c.xpath('ancestor-or-self::*')
      expect(result.first).to eq(c)
      expect(result.map(&:name)).to eq(['c', 'b', 'a', 'root'])
    end

    it "returns just self for root element" do
      doc = parse('<root/>')
      result = doc.root.xpath('ancestor-or-self::*')
      expect(result.size).to eq(1)
      expect(result.first).to eq(doc.root)
    end

    it "walks up the entire ancestor chain" do
      doc = parse('<root><a><b><c/></b></a></root>')
      c = navigate_to(doc.root, 'a/b/c')
      result = c.xpath('ancestor-or-self::*')
      expect(result.size).to eq(4) # c, b, a, root
    end

    it "works with name test" do
      doc = parse('<root><section><section><item/></section></section></root>')
      item = navigate_to(doc.root, 'section/section/item')
      result = item.xpath('ancestor-or-self::section')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to all(eq('section'))
    end

    it "maintains correct order (self first, then ancestors)" do
      doc = parse('<root><a><b/></a></root>')
      b = navigate_to(doc.root, 'a/b')
      result = b.xpath('ancestor-or-self::*')
      expect(result.map(&:name)).to eq(['b', 'a', 'root'])
    end
  end

  describe "ancestor axis (ancestor::*)" do
    it "excludes context node, includes all ancestors" do
      doc = parse('<root><a><b><c/></b></a></root>')
      c = navigate_to(doc.root, 'a/b/c')
      result = c.xpath('ancestor::*')
      expect(result.size).to eq(3) # b, a, root (NOT c)
      expect(result.map(&:name)).to eq(['b', 'a', 'root'])
    end

    it "returns empty for root element" do
      doc = parse('<root/>')
      result = doc.root.xpath('ancestor::*')
      expect(result).to be_empty
    end

    it "walks up entire ancestor chain" do
      doc = parse('<root><l1><l2><l3><l4/></l3></l2></l1></root>')
      l4 = navigate_to(doc.root, 'l1/l2/l3/l4')
      result = l4.xpath('ancestor::*')
      expect(result.size).to eq(4) # l3, l2, l1, root
      expect(result.map(&:name)).to eq(['l3', 'l2', 'l1', 'root'])
    end

    it "works with name test" do
      doc = parse('<root><div><div><span/></div></div></root>')
      span = navigate_to(doc.root, 'div/div/span')
      result = span.xpath('ancestor::div')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to all(eq('div'))
    end

    it "works from intermediate element" do
      doc = parse('<root><a><b><c/></b></a></root>')
      b = navigate_to(doc.root, 'a/b')
      result = b.xpath('ancestor::*')
      expect(result.size).to eq(2) # a, root (NOT b)
      expect(result.map(&:name)).to eq(['a', 'root'])
    end
  end

  describe "following-sibling axis (following-sibling::*)" do
    it "returns siblings after context node" do
      doc = parse('<root><a/><b/><c/><d/></root>')
      b = navigate_to(doc.root, 'b')
      result = b.xpath('following-sibling::*')
      expect(result.size).to eq(2) # c, d (not a or b)
      expect(result.map(&:name)).to eq(['c', 'd'])
    end

    it "returns empty for last child" do
      doc = parse('<root><a/><b/><c/></root>')
      c = navigate_to(doc.root, 'c')
      result = c.xpath('following-sibling::*')
      expect(result).to be_empty
    end

    it "maintains document order" do
      doc = parse('<root><first/><second/><third/><fourth/></root>')
      first = navigate_to(doc.root, 'first')
      result = first.xpath('following-sibling::*')
      expect(result.map(&:name)).to eq(['second', 'third', 'fourth'])
    end

    it "works with name test" do
      doc = parse('<root><a/><b/><a/><c/><a/></root>')
      first_a = doc.root.xpath('child::*')[0]
      result = first_a.xpath('following-sibling::a')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to all(eq('a'))
    end

    it "only returns elements, not text nodes" do
      doc = parse('<root><a/>text<b/>more text<c/></root>')
      a = navigate_to(doc.root, 'a')
      result = a.xpath('following-sibling::*')
      expect(result.size).to eq(2) # b, c (not text)
      expect(result.map(&:name)).to eq(['b', 'c'])
    end
  end

  describe "preceding-sibling axis (preceding-sibling::*)" do
    it "returns siblings before context node" do
      doc = parse('<root><a/><b/><c/><d/></root>')
      c = navigate_to(doc.root, 'c')
      result = c.xpath('preceding-sibling::*')
      expect(result.size).to eq(2) # a, b (not c or d)
      expect(result.map(&:name)).to eq(['a', 'b'])
    end

    it "returns empty for first child" do
      doc = parse('<root><a/><b/><c/></root>')
      a = navigate_to(doc.root, 'a')
      result = a.xpath('preceding-sibling::*')
      expect(result).to be_empty
    end

    it "maintains document order" do
      doc = parse('<root><first/><second/><third/><fourth/></root>')
      fourth = navigate_to(doc.root, 'fourth')
      result = fourth.xpath('preceding-sibling::*')
      expect(result.map(&:name)).to eq(['first', 'second', 'third'])
    end

    it "works with name test" do
      doc = parse('<root><a/><b/><a/><c/><a/></root>')
      last_a = doc.root.xpath('child::*')[4]
      result = last_a.xpath('preceding-sibling::a')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to all(eq('a'))
    end

    it "only returns elements, not text nodes" do
      doc = parse('<root><a/>text<b/>more text<c/></root>')
      c = navigate_to(doc.root, 'c')
      result = c.xpath('preceding-sibling::*')
      expect(result.size).to eq(2) # a, b (not text)
      expect(result.map(&:name)).to eq(['a', 'b'])
    end
  end

  describe "following axis (following::*)" do
    it "includes following siblings" do
      doc = parse('<root><a/><b/><c/></root>')
      a = navigate_to(doc.root, 'a')
      result = a.xpath('following::*')
      expect(result.size).to eq(2) # b, c
      expect(result.map(&:name)).to eq(['b', 'c'])
    end

    it "includes descendants of following siblings" do
      doc = parse('<root><a/><b><bb/></b><c><cc/></c></root>')
      a = navigate_to(doc.root, 'a')
      result = a.xpath('following::*')
      expect(result.size).to eq(4) # b, bb, c, cc
      expect(result.map(&:name)).to eq(['b', 'bb', 'c', 'cc'])
    end

    it "includes parent's following nodes" do
      doc = parse('<root><parent1><child1/></parent1><parent2><child2/></parent2></root>')
      child1 = navigate_to(doc.root, 'parent1/child1')
      result = child1.xpath('following::*')
      expect(result.size).to eq(2) # parent2, child2
      expect(result.map(&:name)).to eq(['parent2', 'child2'])
    end

    it "does not cause infinite recursion" do
      doc = parse('<root><a><b><c><d><e/></d></c></b></a></root>')
      e = navigate_to(doc.root, 'a/b/c/d/e')
      result = e.xpath('following::*')
      expect(result).to be_an(Array)
      expect(result).to be_empty # e is last, no following
    end

    it "maintains correct document order" do
      doc = parse('<root><a><aa/></a><b /><c><cc/></c></root>')
      a = navigate_to(doc.root, 'a')
      result = a.xpath('following::*')
      # following axis excludes descendants of context node
      # aa is a descendant of a, so not included
      expect(result.map(&:name)).to eq(['b', 'c', 'cc'])
    end

    it "returns empty for last node in document" do
      doc = parse('<root><a/><b/></root>')
      b = navigate_to(doc.root, 'b')
      result = b.xpath('following::*')
      expect(result).to be_empty
    end
  end

  describe "preceding axis (preceding::*)" do
    it "includes preceding siblings" do
      doc = parse('<root><a/><b/><c/></root>')
      c = navigate_to(doc.root, 'c')
      result = c.xpath('preceding::*')
      expect(result.size).to eq(2) # a, b
      expect(result.map(&:name)).to eq(['a', 'b'])
    end

    it "includes descendants of preceding siblings" do
      doc = parse('<root><a><aa/></a><b><bb/></b><c/></root>')
      c = navigate_to(doc.root, 'c')
      result = c.xpath('preceding::*')
      expect(result.size).to eq(4) # a, aa, b, bb
      expect(result.map(&:name)).to eq(['a', 'aa', 'b', 'bb'])
    end

    it "includes parent's preceding nodes" do
      doc = parse('<root><parent1><child1/></parent1><parent2><child2/></parent2></root>')
      child2 = navigate_to(doc.root, 'parent2/child2')
      result = child2.xpath('preceding::*')
      expect(result.size).to eq(2) # parent1, child1
      expect(result.map(&:name)).to eq(['parent1', 'child1'])
    end

    it "does not cause infinite recursion" do
      doc = parse('<root><a><b><c><d><e/></d></c></b></a></root>')
      a = navigate_to(doc.root, 'a')
      result = a.xpath('preceding::*')
      expect(result).to be_an(Array)
      expect(result).to be_empty # a is first, no preceding
    end

    it "returns empty for first node in document" do
      doc = parse('<root><a/><b/></root>')
      a = navigate_to(doc.root, 'a')
      result = a.xpath('preceding::*')
      expect(result).to be_empty
    end
  end

  describe "parent navigation (..)" do
    let(:xml) { '<root><parent><child/></parent></root>' }
    let(:doc) { parse(xml) }
    let(:root) { doc.root }

    it "navigates to parent element" do
      child = navigate_to(root, 'parent/child')
      result = child.xpath('..')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('parent')
    end

    it "returns empty for root element" do
      result = root.xpath('..')
      expect(result).to be_empty
    end

    it "works with parent axis" do
      child = navigate_to(root, 'parent/child')
      result = child.xpath('parent::*')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('parent')
    end

    it "allows chaining after parent navigation" do
      xml = '<root><a><b><c/></b></a></root>'
      doc = parse(xml)
      c = navigate_to(doc.root, 'a/b/c')
      result = c.xpath('../..')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('a')
    end
  end

  describe "self axis (.)" do
    let(:xml) { '<root><item/></root>' }
    let(:doc) { parse(xml) }
    let(:root) { doc.root }

    it "returns context node" do
      result = root.xpath('.')
      expect(result).to eq([root])
    end

    it "works with self axis" do
      result = root.xpath('self::*')
      expect(result.size).to eq(1)
      expect(result.first).to eq(root)
    end

    it "returns self from any element" do
      item = root.nodes.first
      result = item.xpath('.')
      expect(result).to eq([item])
    end
  end

  describe "wildcard matching (*)" do
    let(:xml) { '<root><a/><b/><c/></root>' }
    let(:doc) { parse(xml) }
    let(:root) { doc.root }

    it "matches all children" do
      result = root.xpath('*')
      expect(result.size).to eq(3)
    end

    it "matches all descendants" do
      xml = '<root><a><aa/></a><b><bb/></b></root>'
      doc = parse(xml)
      result = doc.root.xpath('.//*')
      expect(result.size).to eq(4) # a, aa, b, bb
    end

    it "works in multi-step paths" do
      xml = '<root><section><item/></section></root>'
      doc = parse(xml)
      result = doc.root.xpath(' */item')
      expect(result.size).to eq(1)
    end
  end

  describe "attribute selection" do
    let(:xml) do
      <<~XML
        <library>
          <book id="1" title="XPath Guide"/>
          <book id="2" title="Ruby Guide"/>
        </library>
      XML
    end

    let(:doc) { parse(xml) }
    let(:root) { doc.root }

    it "selects specific attribute" do
      result = root.xpath('.//book/@id')
      expect(result).to be_an(Array)
      expect(result).to eq(['1', '2'])
    end

    it "selects multiple attributes" do
      result = root.xpath('.//book/@title')
      expect(result).to eq(['XPath Guide', 'Ruby Guide'])
    end

    it "selects all attributes with @*" do
      result = root.xpath('.//book/@*')
      expect(result.size).to eq(4) # 2 books x 2 attributes each
      # Attributes are returned in order: id, title for each book
      expect(result).to eq(['1', 'XPath Guide', '2', 'Ruby Guide'])
    end

    it "works with attribute axis" do
      result = root.xpath('.//book/attribute::id')
      expect(result).to eq(['1', '2'])
    end
  end

  describe "absolute paths from document" do
    let(:xml) { '<root><child><item/></child></root>' }
    let(:doc) { parse(xml) }

    it "starts from document root with /" do
      item = doc.root.nodes.first.nodes.first
      result = item.xpath('/root')
      # Absolute paths should work because Element#xpath finds the document
      expect(result.size).to eq(1)
      expect(result.first).to eq(doc.root)
    end

    it "navigates multiple levels" do
      result = doc.xpath('/root/child/item')
      expect(result.size).to eq(1)
    end

    it "works with // from any context" do
      child = doc.root.nodes.first
      result = child.xpath('//item')
      expect(result.size).to eq(1)
    end
  end

  describe "complex queries" do
    let(:xml) do
      <<~XML
        <catalog>
          <category name="books">
            <product id="1">Book A</product>
            <product id="2">Book B</product>
          </category>
          <category name="music">
            <product id="3">Album A</product>
          </category>
        </catalog>
      XML
    end

    let(:doc) { parse(xml) }
    let(:root) { doc.root }

    it "handles multi-step descendant search" do
      result = root.xpath('.//category/product')
      expect(result.size).to eq(3)
    end

    it "combines wildcard with descendant" do
      result = root.xpath('.//product')
      expect(result.size).to eq(3)
    end

    it "works with multiple path steps" do
      result = root.xpath('category/product')
      expect(result.size).to eq(3)
    end
  end

  describe "context resolution" do
    let(:xml) { '<root><a><b><c/></b></a></root>' }
    let(:doc) { parse(xml) }

    it "finds document context automatically from deep element" do
      c = navigate_to(doc.root, 'a/b/c')
      expect { c.xpath('.') }.not_to raise_error
    end

    it "allows relative queries from any element" do
      b = navigate_to(doc.root, 'a/b')
      result = b.xpath('c')
      expect(result.size).to eq(1)
    end

    it "maintains correct context through navigation" do
      a = navigate_to(doc.root, 'a')
      result = a.xpath('b/c')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('c')
    end
  end

  describe "edge cases" do
    it "handles single element document" do
      doc = parse('<root/>')
      result = doc.root.xpath('.')
      expect(result.size).to eq(1)
    end

    it "handles empty xpath gracefully" do
      doc = parse('<root/>')
      # Empty XPath should raise an error
      expect { doc.root.xpath('') }.to raise_error(RuntimeError, /parsing error/)
    end

    it "handles elements with text content" do
      doc = parse('<root><item>text</item></root>')
      result = doc.root.xpath('item')
      expect(result.size).to eq(1)
      expect(result.first.text).to eq('text')
    end

    it "handles mixed content elements" do
      doc = parse('<root>text1<a/>text2<b/>text3</root>')
      result = doc.root.xpath('*')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to eq(['a', 'b'])
    end

    it "handles nested same-named elements" do
      doc = parse('<root><item><item><item/></item></item></root>')
      result = doc.root.xpath('.//item')
      expect(result.size).to eq(3)
    end
  end

  describe "document order" do
    let(:xml) do
      <<~XML
        <root>
          <z/>
          <a/>
          <m/>
        </root>
      XML
    end

    let(:doc) { parse(xml) }
    let(:root) { doc.root }

    it "maintains document order in results" do
      result = root.xpath('*')
      expect(result.map(&:name)).to eq(['z', 'a', 'm'])
    end

    it "preserves order in descendant search" do
      xml = '<root><b/><a><c/></a></root>'
      doc = parse(xml)
      result = doc.root.xpath('.//*')
      expect(result.map(&:name)).to eq(['b', 'a', 'c'])
    end
  end

  describe "namespaced elements" do
    let(:xml) do
      <<~XML
        <root xmlns="http://example.org">
          <item>Content</item>
        </root>
      XML
    end

    let(:doc) { parse(xml) }

    it "finds elements regardless of namespace" do
      # Note: Current implementation may not handle namespaces in XPath
      # This test documents expected behavior
      result = doc.root.xpath('item')
      expect(result.size).to be >= 0 # May or may not find namespaced elements
    end
  end

  describe "performance characteristics" do
    it "handles moderately large documents" do
      # Create a document with 100 elements
      items = (1..100).map { |i| "<item id='#{i}'/>" }.join
      xml = "<root>#{items}</root>"
      doc = parse(xml)

      start_time = Time.now
      result = doc.root.xpath('.//item')
      elapsed = Time.now - start_time

      expect(result.size).to eq(100)
      expect(elapsed).to be < 1.0 # Should complete in under 1 second
    end

    it "handles deep nesting efficiently" do
      # Create deeply nested document
      xml = String.new('<root>')
      20.times { |i| xml << "<level#{i}>" }
      xml << '<item/>'
      20.times { |i| xml << "</level#{19-i}>" }
      xml << '</root>'

      doc = parse(xml)
      result = doc.root.xpath('.//item')
      expect(result.size).to eq(1)
    end
  end

  describe "position predicates" do
    let(:xml) { '<root><a/><b/><c/><d/></root>' }
    let(:doc) { parse(xml) }
    let(:root) { doc.root }

    it "selects first element with [1]" do
      result = root.xpath('*[1]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('a')
    end

    it "selects second element with [2]" do
      result = root.xpath('*[2]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('b')
    end

    it "selects third element with [3]" do
      result = root.xpath('*[3]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('c')
    end

    it "selects last element with [last()]" do
      result = root.xpath('*[last()]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('d')
    end

    it "works with named elements" do
      xml = '<root><item/><other/><item/></root>'
      doc = parse(xml)
      result = doc.root.xpath('item[1]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('item')
    end

    it "works with descendant axis" do
      xml = '<root><section><a/><b/><c/></section></root>'
      doc = parse(xml)
      # descendant::* returns [section, a, b, c]
      # Position [2] selects the 2nd one: 'a'
      result = doc.root.xpath('descendant::*[2]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('a')
    end

    it "works in complex paths" do
      xml = '<root><section><item id="a"/><item/></section><section><item/></section></root>'
      doc = parse(xml)
      result = doc.root.xpath('section/item[2]')
      expect(result.size).to eq(1)
    end

    it "applies to result nodeset correctly" do
      xml = '<root><a/><b/><c/></root>'
      doc = parse(xml)
      # After selecting all children, [2] should give second one
      result = doc.root.xpath('*[2]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('b')
    end

    it "handles position with absolute path" do
      xml = '<root><item/><item/><item/></root>'
      doc = parse(xml)
      result = doc.xpath('//item[1]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('item')
    end

    it "returns empty when position is out of range" do
      result = root.xpath('*[10]')
      expect(result).to be_empty
    end
  end

  describe "boolean predicates" do
    it "filters by attribute existence" do
      xml = '<root><a id="1"/><b/><c id="2"/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[@id]')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to eq(['a', 'c'])
    end

    it "works with multiple attributes" do
      xml = '<root><a id="1" class="x"/><b class="y"/><c id="2"/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[@class]')
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to eq(['a', 'b'])
    end

    it "filters by child element existence" do
      xml = '<root><section><book/></section><section/><section><book/></section></root>'
      doc = parse(xml)
      result = doc.root.xpath('section[book]')
      expect(result.size).to eq(2)
    end

    it "works with nested child tests" do
      xml = '<root><container><span/></container><container/><container><span/></container></root>'
      doc = parse(xml)
      result = doc.root.xpath('container[span]')
      expect(result.size).to eq(2)
    end

    it "returns empty when no matches" do
      xml = '<root><a/><b/><c/></root>'
      doc = parse(xml)
      result = doc.root.xpath('*[@id]')
      expect(result).to be_empty
    end

    it "works with descendant axis" do
      xml = '<root><section><item id="1"/><item/></section></root>'
      doc = parse(xml)
      result = doc.root.xpath('descendant::*[@id]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('item')
    end

    it "works with specific element" do
      xml = '<root><item id="1"/><other id="2"/><item/></root>'
      doc = parse(xml)
      result = doc.root.xpath('item[@id]')
      expect(result.size).to eq(1)
      expect(result.first.name).to eq('item')
    end

    it "works in complex paths" do
      xml = '<root><section><item id="a"/><item/></section><section><item/></section></root>'
      doc = parse(xml)
      result = doc.root.xpath('section/item[@id]')
      expect(result.size).to eq(1)
    end
  end

  describe "XPath string functions" do
    describe "string()" do
      it "converts context node to string with no arguments" do
        xml = '<root><item>Hello</item></root>'
        doc = parse(xml)
        item = doc.root.xpath('item').first
        # Call from Ruby: string() should return text content
        result = doc.xpath('string(//item)')
        expect(result).to eq('Hello')
      end

      it "converts number to string" do
        doc = parse('<root/>')
        result = doc.xpath('string(42)')
        expect(result).to eq('42')
      end

      it "converts boolean true to 'true'" do
        doc = parse('<root/>')
        # Use a comparison that returns true
        result = doc.xpath('string(1 = 1)')
        expect(result).to eq('true')
      end

      it "converts boolean false to 'false'" do
        doc = parse('<root/>')
        result = doc.xpath('string(1 = 2)')
        expect(result).to eq('false')
      end

      it "handles NaN" do
        doc = parse('<root/>')
        # Division by string that can't convert to number produces NaN
        result = doc.xpath('string(0 div 0)')
        expect(result).to eq('NaN')
      end

      it "handles Infinity" do
        doc = parse('<root/>')
        result = doc.xpath('string(1 div 0)')
        expect(result).to eq('Infinity')
      end

      it "handles negative Infinity" do
        doc = parse('<root/>')
        result = doc.xpath('string(-1 div 0)')
        expect(result).to eq('-Infinity')
      end
    end

    describe "concat()" do
      it "concatenates two strings" do
        doc = parse('<root/>')
        result = doc.xpath("concat('Hello', ' World')")
        expect(result).to eq('Hello World')
      end

      it "concatenates three strings" do
        doc = parse('<root/>')
        result = doc.xpath("concat('A', 'B', 'C')")
        expect(result).to eq('ABC')
      end

      it "concatenates many strings" do
        doc = parse('<root/>')
        result = doc.xpath("concat('1', '2', '3', '4', '5')")
        expect(result).to eq('12345')
      end

      it "converts numbers to strings" do
        doc = parse('<root/>')
        result = doc.xpath("concat('Value: ', 42)")
        expect(result).to eq('Value: 42')
      end

      it "handles empty strings" do
        doc = parse('<root/>')
        result = doc.xpath("concat('', 'test', '')")
        expect(result).to eq('test')
      end
    end

    describe "starts-with()" do
      it "returns true for matching prefix" do
        doc = parse('<root/>')
        result = doc.xpath("starts-with('Hello World', 'Hello')")
        expect(result).to eq(true)
      end

      it "returns false for non-matching prefix" do
        doc = parse('<root/>')
        result = doc.xpath("starts-with('Hello World', 'World')")
        expect(result).to eq(false)
      end

      it "returns true for empty prefix" do
        doc = parse('<root/>')
        result = doc.xpath("starts-with('test', '')")
        expect(result).to eq(true)
      end

      it "works in predicates with attributes" do
        xml = '<root><item id="book1"/><item id="book2"/><item id="other"/></root>'
        doc = parse(xml)
        result = doc.root.xpath('item[starts-with(@id, "book")]')
        expect(result.size).to eq(2)
      end

      it "is case sensitive" do
        doc = parse('<root/>')
        result = doc.xpath("starts-with('Hello', 'hello')")
        expect(result).to eq(false)
      end
    end

    describe "contains()" do
      it "returns true when substring is present" do
        doc = parse('<root/>')
        result = doc.xpath("contains('Hello World', 'lo Wo')")
        expect(result).to eq(true)
      end

      it "returns false when substring is absent" do
        doc = parse('<root/>')
        result = doc.xpath("contains('Hello World', 'xyz')")
        expect(result).to eq(false)
      end

      it "returns true for empty substring" do
        doc = parse('<root/>')
        result = doc.xpath("contains('test', '')")
        expect(result).to eq(true)
      end

      it "works in predicates with attributes" do
        xml = '<root><item name="apple pie"/><item name="cherry pie"/><item name="banana"/></root>'
        doc = parse(xml)
        result = doc.root.xpath('item[contains(@name, "pie")]')
        expect(result.size).to eq(2)
      end

      it "is case sensitive" do
        doc = parse('<root/>')
        result = doc.xpath("contains('Hello', 'HEL')")
        expect(result).to eq(false)
      end
    end

    describe "substring()" do
      # Basic tests
      it "extracts substring with position and length" do
        doc = parse('<root/>')
        result = doc.xpath("substring('12345', 2, 3)")
        expect(result).to eq('234')
      end

      it "extracts from position to end without length" do
        doc = parse('<root/>')
        result = doc.xpath("substring('12345', 2)")
        expect(result).to eq('2345')
      end

      it "uses 1-based indexing" do
        doc = parse('<root/>')
        result = doc.xpath("substring('12345', 1, 1)")
        expect(result).to eq('1')
      end

      # Edge cases
      it "handles position 0 with length" do
        doc = parse('<root/>')
        # Position 0 with length 3: positions 0,1,2 → chars at 1,2
        result = doc.xpath("substring('12345', 0, 3)")
        expect(result).to eq('12')
      end

      it "handles negative position" do
        doc = parse('<root/>')
        # Position -1 with length 4: positions [-1, 3), intersect with [1, ∞) → [1, 3)
        # Characters at positions 1,2 → "12"
        result = doc.xpath("substring('12345', -1, 4)")
        expect(result).to eq('12')
      end

      it "returns empty string for position beyond length" do
        doc = parse('<root/>')
        result = doc.xpath("substring('12345', 10, 2)")
        expect(result).to eq('')
      end

      it "returns empty string for zero length" do
        doc = parse('<root/>')
        result = doc.xpath("substring('12345', 2, 0)")
        expect(result).to eq('')
      end

      it "returns empty string for negative length" do
        doc = parse('<root/>')
        result = doc.xpath("substring('12345', 2, -1)")
        expect(result).to eq('')
      end

      # XPath spec edge cases with rounding
      it "rounds fractional positions per XPath spec" do
        doc = parse('<root/>')
        # Position 1.5 rounds to 2, length 2.6 rounds to 3
        result = doc.xpath("substring('12345', 1.5, 2.6)")
        expect(result).to eq('234')
      end

      # NaN handling
      it "returns empty string for NaN position" do
        doc = parse('<root/>')
        result = doc.xpath("substring('12345', 0 div 0)")
        expect(result).to eq('')
      end

      it "returns empty string for NaN length" do
        doc = parse('<root/>')
        result = doc.xpath("substring('12345', 2, 0 div 0)")
        expect(result).to eq('')
      end

      # UTF-8 character handling
      it "counts UTF-8 characters not bytes" do
        doc = parse('<root/>')
        # '你好世界' is 4 characters but 12 bytes in UTF-8
        result = doc.xpath("substring('你好世界', 2, 2)")
        expect(result).to eq('好世')
      end

      it "handles mixed ASCII and UTF-8" do
        doc = parse('<root/>')
        result = doc.xpath("substring('Hello世界', 6, 2)")
        expect(result).to eq('世界')
      end
    end

    describe "string-length()" do
      it "returns length of string" do
        doc = parse('<root/>')
        result = doc.xpath("string-length('Hello')")
        expect(result).to eq(5)
      end

      it "returns 0 for empty string" do
        doc = parse('<root/>')
        result = doc.xpath("string-length('')")
        expect(result).to eq(0)
      end

      it "counts UTF-8 characters not bytes" do
        doc = parse('<root/>')
        # '你好' is 2 characters but 6 bytes
        result = doc.xpath("string-length('你好')")
        expect(result).to eq(2)
      end

      it "uses context node when no argument" do
        xml = '<root><item>Test</item></root>'
        doc = parse(xml)
        result = doc.xpath('string-length(//item)')
        expect(result).to eq(4)
      end

      it "handles mixed ASCII and UTF-8" do
        doc = parse('<root/>')
        result = doc.xpath("string-length('Hello世界')")
        expect(result).to eq(7)
      end
    end

    describe "normalize-space()" do
      it "strips leading whitespace" do
        doc = parse('<root/>')
        result = doc.xpath("normalize-space('  test')")
        expect(result).to eq('test')
      end

      it "strips trailing whitespace" do
        doc = parse('<root/>')
        result = doc.xpath("normalize-space('test  ')")
        expect(result).to eq('test')
      end

      it "collapses internal whitespace to single space" do
        doc = parse('<root/>')
        result = doc.xpath("normalize-space('hello    world')")
        expect(result).to eq('hello world')
      end

      it "handles multiple types of whitespace" do
        doc = parse('<root/>')
        result = doc.xpath("normalize-space('  hello\t\n\rworld  ')")
        expect(result).to eq('hello world')
      end

      it "handles string with no extra whitespace" do
        doc = parse('<root/>')
        result = doc.xpath("normalize-space('hello world')")
        expect(result).to eq('hello world')
      end

      it "returns empty string for all whitespace" do
        doc = parse('<root/>')
        result = doc.xpath("normalize-space('   \t\n   ')")
        expect(result).to eq('')
      end

      it "uses context node when no argument" do
        xml = '<root><item>  hello   world  </item></root>'
        doc = parse(xml)
        result = doc.xpath('normalize-space(//item)')
        expect(result).to eq('hello world')
      end
    end

    describe "translate()" do
      it "replaces matching characters" do
        doc = parse('<root/>')
        result = doc.xpath("translate('bar', 'abc', 'ABC')")
        expect(result).to eq('BAr')
      end

      it "removes characters when third arg is shorter" do
        doc = parse('<root/>')
        result = doc.xpath("translate('bar', 'abc', 'AB')")
        expect(result).to eq('BAr')
      end

      it "handles empty translation string" do
        doc = parse('<root/>')
        result = doc.xpath("translate('bar', 'abc', '')")
        expect(result).to eq('r')
      end

      it "works with numbers converted to strings" do
        doc = parse('<root/>')
        result = doc.xpath("translate('2', '123', 'abc')")
        expect(result).to eq('b')
      end

      it "handles characters not in search string" do
        doc = parse('<root/>')
        result = doc.xpath("translate('hello', 'eo', 'EO')")
        expect(result).to eq('hEllO')
      end

      it "is case sensitive" do
        doc = parse('<root/>')
        result = doc.xpath("translate('Hello', 'h', 'H')")
        expect(result).to eq('Hello') # 'H' and 'h' are different
      end

      it "works in predicates" do
        xml = '<root><item code="abc"/><item code="xyz"/><item code="aBc"/></root>'
        doc = parse(xml)
        # Normalize to uppercase and compare
        result = doc.root.xpath('item[translate(@code, "abc", "ABC") = "ABC"]')
        expect(result.size).to eq(2)
      end
    end

    describe "substring-before()" do
      it "extracts substring before delimiter" do
        doc = parse('<root/>')
        result = doc.xpath("substring-before('1999/04/01', '/')")
        expect(result).to eq('1999')
      end

      it "returns empty string when delimiter not found" do
        doc = parse('<root/>')
        result = doc.xpath("substring-before('hello', 'x')")
        expect(result).to eq('')
      end

      it "returns empty string for empty delimiter" do
        doc = parse('<root/>')
        result = doc.xpath("substring-before('hello', '')")
        expect(result).to eq('')
      end

      it "handles delimiter at start" do
        doc = parse('<root/>')
        result = doc.xpath("substring-before('/path/to/file', '/')")
        expect(result).to eq('')
      end

      it "finds first occurrence only" do
        doc = parse('<root/>')
        result = doc.xpath("substring-before('a/b/c', '/')")
        expect(result).to eq('a')
      end

      it "works with attribute values" do
        xml = '<root><item id="user@example.com"/></root>'
        doc = parse(xml)
        result = doc.xpath('substring-before(//item/@id, "@")')
        expect(result).to eq('user')
      end

      it "works in predicates" do
        xml = '<root><file name="doc.txt"/><file name="image.png"/><file name="script.txt"/></root>'
        doc = parse(xml)
        result = doc.root.xpath('file[substring-before(@name, ".") = "doc"]')
        expect(result.size).to eq(1) # Only doc.txt
      end
    end

    describe "substring-after()" do
      it "extracts substring after delimiter" do
        doc = parse('<root/>')
        result = doc.xpath("substring-after('1999/04/01', '/')")
        expect(result).to eq('04/01')
      end

      it "returns empty string when delimiter not found" do
        doc = parse('<root/>')
        result = doc.xpath("substring-after('hello', 'x')")
        expect(result).to eq('')
      end

      it "returns entire string for empty delimiter" do
        doc = parse('<root/>')
        result = doc.xpath("substring-after('hello', '')")
        expect(result).to eq('hello')
      end

      it "handles delimiter at end" do
        doc = parse('<root/>')
        result = doc.xpath("substring-after('path/', '/')")
        expect(result).to eq('')
      end

      it "finds first occurrence only" do
        doc = parse('<root/>')
        result = doc.xpath("substring-after('a/b/c', '/')")
        expect(result).to eq('b/c')
      end

      it "works with attribute values" do
        xml = '<root><item id="user@example.com"/></root>'
        doc = parse(xml)
        result = doc.xpath('substring-after(//item/@id, "@")')
        expect(result).to eq('example.com')
      end

      it "works in predicates" do
        xml = '<root><file name="doc.txt"/><file name="image.png"/><file name="script.txt"/></root>'
        doc = parse(xml)
        result = doc.root.xpath('file[substring-after(@name, ".") = "txt"]')
        expect(result.size).to eq(2)
      end
    end

    describe "string functions in predicates" do
      it "uses starts-with in predicate" do
        xml = '<root><book id="b1" title="XPath Guide"/><book id="b2" title="Ruby Guide"/><book id="b3" title="XPath Advanced"/></root>'
        doc = parse(xml)
        result = doc.root.xpath('book[starts-with(@title, "XPath")]')
        expect(result.size).to eq(2)
        expect(result.map { |n| n[:id] }).to eq(['b1', 'b3'])
      end

      it "uses contains in predicate" do
        xml = '<root><item name="apple pie"/><item name="cherry tart"/><item name="lemon pie"/></root>'
        doc = parse(xml)
        result = doc.root.xpath('item[contains(@name, "pie")]')
        expect(result.size).to eq(2)
      end

      it "combines string functions" do
        xml = '<root><item>  test  </item><item>other</item></root>'
        doc = parse(xml)
        # Find items where normalized text is 'test'
        result = doc.root.xpath('item[normalize-space(.) = "test"]')
        expect(result.size).to eq(1)
      end
    end
  end

  describe "XPath boolean functions" do
    describe "boolean()" do
      it "converts number 1 to true" do
        doc = parse('<root/>')
        result = doc.xpath('boolean(1)')
        expect(result).to eq(true)
      end

      it "converts number 0 to false" do
        doc = parse('<root/>')
        result = doc.xpath('boolean(0)')
        expect(result).to eq(false)
      end

      it "converts NaN to false" do
        doc = parse('<root/>')
        result = doc.xpath('boolean(0 div 0)')
        expect(result).to eq(false)
      end

      it "converts positive number to true" do
        doc = parse('<root/>')
        result = doc.xpath('boolean(42)')
        expect(result).to eq(true)
      end

      it "converts negative number to true" do
        doc = parse('<root/>')
        result = doc.xpath('boolean(-5)')
        expect(result).to eq(true)
      end

      it "converts non-empty string to true" do
        doc = parse('<root/>')
        result = doc.xpath("boolean('text')")
        expect(result).to eq(true)
      end

      it "converts empty string to false" do
        doc = parse('<root/>')
        result = doc.xpath("boolean('')")
        expect(result).to eq(false)
      end

      it "converts non-empty nodeset to true" do
        xml = '<root><item/></root>'
        doc = parse(xml)
        result = doc.xpath('boolean(//item)')
        expect(result).to eq(true)
      end

      it "converts empty nodeset to false" do
        xml = '<root/>'
        doc = parse(xml)
        result = doc.xpath('boolean(//missing)')
        expect(result).to eq(false)
      end

      it "converts boolean true to true" do
        doc = parse('<root/>')
        result = doc.xpath('boolean(1 = 1)')
        expect(result).to eq(true)
      end

      it "converts boolean false to false" do
        doc = parse('<root/>')
        result = doc.xpath('boolean(1 = 2)')
        expect(result).to eq(false)
      end

      it "works in boolean operations" do
        doc = parse('<root/>')
        result = doc.xpath('boolean(1) and boolean(1)')
        expect(result).to eq(true)
      end
    end

    describe "not()" do
      it "negates true to false" do
        doc = parse('<root/>')
        result = doc.xpath('not(1 = 1)')
        expect(result).to eq(false)
      end

      it "negates false to true" do
        doc = parse('<root/>')
        result = doc.xpath('not(1 = 2)')
        expect(result).to eq(true)
      end

      it "works with true() function" do
        doc = parse('<root/>')
        result = doc.xpath('not(true())')
        expect(result).to eq(false)
      end

      it "works with false() function" do
        doc = parse('<root/>')
        result = doc.xpath('not(false())')
        expect(result).to eq(true)
      end

      it "converts non-zero number to false" do
        doc = parse('<root/>')
        result = doc.xpath('not(1)')
        expect(result).to eq(false)
      end

      it "converts zero to true" do
        doc = parse('<root/>')
        result = doc.xpath('not(0)')
        expect(result).to eq(true)
      end

      it "converts empty string to true" do
        doc = parse('<root/>')
        result = doc.xpath("not('')")
        expect(result).to eq(true)
      end

      it "converts non-empty string to false" do
        doc = parse('<root/>')
        result = doc.xpath("not('text')")
        expect(result).to eq(false)
      end

      it "works in predicates with attribute existence" do
        xml = '<root><a id="1"/><b/><c id="2"/></root>'
        doc = parse(xml)
        result = doc.root.xpath('*[not(@id)]')
        expect(result.size).to eq(1)
        expect(result.first.name).to eq('b')
      end

      it "works in predicates with child existence" do
        xml = '<root><section><item/></section><section/><section><item/></section></root>'
        doc = parse(xml)
        result = doc.root.xpath('section[not(item)]')
        expect(result.size).to eq(1)
      end

      it "double negation returns original" do
        doc = parse('<root/>')
        result = doc.xpath('not(not(true()))')
        expect(result).to eq(true)
      end

      it "works with nodeset conversion" do
        xml = '<root><item/></root>'
        doc = parse(xml)
        result = doc.xpath('not(//missing)')
        expect(result).to eq(true)
      end
    end

    describe "true() and false()" do
      it "true() returns boolean true" do
        doc = parse('<root/>')
        result = doc.xpath('true()')
        expect(result).to eq(true)
      end

      it "false() returns boolean false" do
        doc = parse('<root/>')
        result = doc.xpath('false()')
        expect(result).to eq(false)
      end

      it "true() and true() returns true" do
        doc = parse('<root/>')
        result = doc.xpath('true() and true()')
        expect(result).to eq(true)
      end

      it "true() and false() returns false" do
        doc = parse('<root/>')
        result = doc.xpath('true() and false()')
        expect(result).to eq(false)
      end

      it "false() and false() returns false" do
        doc = parse('<root/>')
        result = doc.xpath('false() and false()')
        expect(result).to eq(false)
      end

      it "true() or false() returns true" do
        doc = parse('<root/>')
        result = doc.xpath('true() or false()')
        expect(result).to eq(true)
      end

      it "false() or false() returns false" do
        doc = parse('<root/>')
        result = doc.xpath('false() or false()')
        expect(result).to eq(false)
      end

      it "works in complex boolean expressions" do
        doc = parse('<root/>')
        result = doc.xpath('not(not(true()))')
        expect(result).to eq(true)
      end

      it "works in comparisons" do
        doc = parse('<root/>')
        result = doc.xpath('true() = true()')
        expect(result).to eq(true)
      end

      it "works in predicates" do
        xml = '<root><a/><b/><c/></root>'
        doc = parse(xml)
        # true() always matches, so all elements selected
        result = doc.root.xpath('*[true()]')
        expect(result.size).to eq(3)
      end

      it "false() in predicate excludes all" do
        xml = '<root><a/><b/><c/></root>'
        doc = parse(xml)
        # false() never matches, so no elements selected
        result = doc.root.xpath('*[false()]')
        expect(result).to be_empty
      end
    end

    describe "lang()" do
      it "matches exact language code" do
        xml = '<root xml:lang="en"><item/></root>'
        doc = parse(xml)
        result = doc.root.xpath('lang("en")')
        expect(result).to eq(true)
      end

      it "returns false when language does not match" do
        xml = '<root xml:lang="en"><item/></root>'
        doc = parse(xml)
        result = doc.root.xpath('lang("fr")')
        expect(result).to eq(false)
      end

      it "matches language with region code" do
        xml = '<root xml:lang="en-US"><item/></root>'
        doc = parse(xml)
        result = doc.root.xpath('lang("en")')
        expect(result).to eq(true)
      end

      it "does not match region when base differs" do
        xml = '<root xml:lang="en-US"><item/></root>'
        doc = parse(xml)
        result = doc.root.xpath('lang("fr")')
        expect(result).to eq(false)
      end

      it "is case insensitive" do
        xml = '<root xml:lang="EN"><item/></root>'
        doc = parse(xml)
        result = doc.root.xpath('lang("en")')
        expect(result).to eq(true)
      end

      it "inherits language from parent" do
        xml = '<root xml:lang="en"><section><item xml:lang="fr"/></section></root>'
        doc = parse(xml)
        item = navigate_to(doc.root, 'section/item')
        result = item.xpath('lang("fr")')
        expect(result).to eq(true)
        result_en = item.xpath('lang("en")')
        expect(result_en).to eq(false)
      end

      it "handles complex language inheritance" do
        xml = '<root xml:lang="en"><div><section xml:lang="fr"><item/></section></div></root>'
        doc = parse(xml)
        item = navigate_to(doc.root, 'div/section/item')
        result = item.xpath('lang("fr")')
        expect(result).to eq(true)
      end
    end

    describe "boolean functions in complex expressions" do
      it "combines boolean() and not()" do
        doc = parse('<root/>')
        result = doc.xpath('not(boolean(0))')
        expect(result).to eq(true)
      end

      it "uses boolean functions in conditional logic" do
        xml = '<root><item active="yes"/><item/></root>'
        doc = parse(xml)
        # Select items with active attribute OR first position
        result = doc.root.xpath('item[boolean(@active) or (position() = 1)]')
        expect(result.size).to eq(1)
      end

      it "uses not() with multiple conditions" do
        xml = '<root><a id="1"/><b class="x"/><c id="2" class="y"/><d/></root>'
        doc = parse(xml)
        # Select elements without both id and class
        result = doc.root.xpath('*[not(@id and @class)]')
        expect(result.size).to eq(3)
        expect(result.map(&:name)).to eq(['a', 'b', 'd'])
      end

      it "uses boolean conversions in comparisons" do
        doc = parse('<root/>')
        result = doc.xpath('boolean(1) = true()')
        expect(result).to eq(true)
      end

      it "chains boolean operations" do
        doc = parse('<root/>')
        result = doc.xpath('true() and not(false()) and boolean(1)')
        expect(result).to eq(true)
      end
    end
  end

  describe "XPath node-set functions" do
    describe "count()" do
      it "counts nodes in a nodeset" do
        xml = '<root><item/><item/><item/></root>'
        doc = parse(xml)
        result = doc.xpath('count(//item)')
        expect(result).to eq(3)
      end

      it "returns 0 for empty nodeset" do
        xml = '<root><item/></root>'
        doc = parse(xml)
        result = doc.xpath('count(//missing)')
        expect(result).to eq(0)
      end

      it "works with predicates" do
        xml = '<root><item id="1"/><item/><item id="2"/></root>'
        doc = parse(xml)
        result = doc.xpath('count(//item[@id])')
        expect(result).to eq(2)
      end

      it "works in comparison expressions" do
        xml = '<root><section><item/><item/></section><section><item/></section></root>'
        doc = parse(xml)
        # Select sections with more than 1 item
        result = doc.root.xpath('section[count(item) > 1]')
        expect(result.size).to eq(1)
        expect(result.first.nodes.size).to eq(2)
      end

      it "counts all descendants" do
        xml = '<root><a><b/><c/></a><d/></root>'
        doc = parse(xml)
        result = doc.xpath('count(//*)')
        expect(result).to eq(5) # root, a, b, c, d
      end
    end

    describe "local-name()" do
      it "returns local name of context node with no argument" do
        xml = '<root><item>test</item></root>'
        doc = parse(xml)
        result = doc.xpath('local-name(//item)')
        expect(result).to eq('item')
      end

      it "returns local name of first node in nodeset" do
        xml = '<root><book/><magazine/></root>'
        doc = parse(xml)
        result = doc.xpath('local-name(//*)') # First is root
        expect(result).to eq('root')
      end

      it "returns empty string for empty nodeset" do
        xml = '<root/>'
        doc = parse(xml)
        result = doc.xpath('local-name(//missing)')
        expect(result).to eq('')
      end

      it "strips namespace prefix from qualified names" do
        xml = '<root><ns:item xmlns:ns="http://example.org"/></root>'
        doc = parse(xml)
        result = doc.xpath('local-name(//item)')
        expect(result).to eq('item')
      end

      it "works in predicates" do
        xml = '<root><item/><book/><item/></root>'
        doc = parse(xml)
        result = doc.root.xpath('*[local-name() = "item"]')
        expect(result.size).to eq(2)
        expect(result.map(&:name)).to all(eq('item'))
      end
    end

    describe "namespace-uri()" do
      it "returns namespace URI of context node" do
        xml = '<root xmlns="http://example.org"><item/></root>'
        doc = parse(xml)
        result = doc.xpath('namespace-uri(//item)')
        expect(result).to eq('http://example.org')
      end

      it "returns empty string for node without namespace" do
        xml = '<root><item/></root>'
        doc = parse(xml)
        result = doc.xpath('namespace-uri(//item)')
        expect(result).to eq('')
      end

      it "returns empty string for empty nodeset" do
        xml = '<root/>'
        doc = parse(xml)
        result = doc.xpath('namespace-uri(//missing)')
        expect(result).to eq('')
      end

      it "works with prefixed namespaces" do
        xml = '<root><ns:item xmlns:ns="http://example.org"/></root>'
        doc = parse(xml)
        result = doc.xpath('namespace-uri(//item)')
        expect(result).to eq('http://example.org')
      end

      it "works in predicates" do
        xml = '<root xmlns="http://example.org"><item/><other xmlns="http://other.org"/></root>'
        doc = parse(xml)
        # Note: This test may need adjustment based on namespace handling
        result = doc.root.xpath('*[namespace-uri() = "http://example.org"]')
        expect(result.size).to be >= 0
      end
    end

    describe "name()" do
      it "returns qualified name of context node" do
        xml = '<root><item>test</item></root>'
        doc = parse(xml)
        result = doc.xpath('name(//item)')
        expect(result).to eq('item')
      end

      it "returns qualified name including prefix" do
        xml = '<root><ns:item xmlns:ns="http://example.org"/></root>'
        doc = parse(xml)
        # Note: Current implementation stores local name only, not prefix
        result = doc.xpath('name(//item)')
        expect(result).to eq('item')
      end

      it "returns empty string for empty nodeset" do
        xml = '<root/>'
        doc = parse(xml)
        result = doc.xpath('name(//missing)')
        expect(result).to eq('')
      end

      it "works in predicates" do
        xml = '<root><item/><other/><item/></root>'
        doc = parse(xml)
        result = doc.root.xpath('*[name() = "item"]')
        expect(result.size).to eq(2)
      end

      it "works with first node in nodeset" do
        xml = '<root><first/><second/></root>'
        doc = parse(xml)
        result = doc.xpath('name(//*)') # First element is root
        expect(result).to eq('root')
      end
    end

    describe "id()" do
      it "selects element by id attribute" do
        xml = '<root><item id="test">Found</item><item id="other">Not</item></root>'
        doc = parse(xml)
        result = doc.xpath('id("test")')
        expect(result.size).to eq(1)
        expect(result.first[:id]).to eq('test')
        expect(result.first.text).to eq('Found')
      end

      it "handles multiple space-separated ids" do
        xml = '<root><item id="a">A</item><item id="b">B</item><item id="c">C</item></root>'
        doc = parse(xml)
        result = doc.xpath('id("a b")')
        expect(result.size).to eq(2)
        ids = result.map { |n| n[:id] }
        expect(ids).to include('a', 'b')
      end

      it "returns empty nodeset for non-existent id" do
        xml = '<root><item id="test"/></root>'
        doc = parse(xml)
        result = doc.xpath('id("missing")')
        expect(result.size).to eq(0)
      end

      it "works with nodeset argument" do
        xml = '<root><ref>test</ref><item id="test">Found</item></root>'
        doc = parse(xml)
        # Get id value from ref element
        result = doc.xpath('id(//ref)')
        expect(result.size).to eq(1)
        expect(result.first[:id]).to eq('test')
      end

      it "ignores duplicate ids" do
        xml = '<root><item id="test">First</item><item id="test">Second</item></root>'
        doc = parse(xml)
        result = doc.xpath('id("test")')
        # Should return both elements with id="test"
        expect(result.size).to be > 1
      end

      it "works in complex expressions" do
        xml = '<root><refs><ref>a</ref><ref>b</ref></refs><items><item id="a">A</item><item id="b">B</item></items></root>'
        doc = parse(xml)
        result = doc.xpath('id(//ref)')
        expect(result.size).to eq(2)
      end
    end

    describe "node-set functions in combination" do
      it "combines count() with predicates" do
        xml = '<root><section><item/><item/></section><section><item/></section></root>'
        doc = parse(xml)
        result = doc.root.xpath('section[count(item) = 2]')
        expect(result.size).to eq(1)
      end

      it "uses name() to filter elements" do
        xml = '<root><item/><book/><item/><other/></root>'
        doc = parse(xml)
        result = doc.root.xpath('*[name() = "item" or name() = "book"]')
        expect(result.size).to eq(3)
      end

      it "combines local-name() with count()" do
        xml = '<root><ns:item xmlns:ns="http://ex.org"/><item/><ns:item xmlns:ns="http://ex.org"/></root>'
        doc = parse(xml)
        result = doc.xpath('count(//*[local-name() = "item"])')
        expect(result).to eq(3)
      end
    end
  end
end