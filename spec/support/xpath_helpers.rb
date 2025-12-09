# frozen_string_literal: true

module XPathHelpers
  # Parse XML string into a Taurus document
  def parse(xml)
    Taurus.parse(xml)
  end

  # Execute XPath query on a node
  def xpath(node, expression)
    node.xpath(expression)
  end

  # Verify XPath result with comprehensive checks
  def expect_xpath_result(node, expression, expected_count: nil, expected_names: nil, expected_values: nil, expected_types: nil)
    result = node.xpath(expression)

    expect(result).to be_an(Array), "XPath result should be an Array"
    
    if expected_count
      expect(result.size).to eq(expected_count), 
        "Expected #{expected_count} results, got #{result.size}"
    end

    if expected_names
      names = result.map { |e| e.respond_to?(:name) ? e.name : nil }.compact
      expect(names).to eq(expected_names),
        "Expected names #{expected_names.inspect}, got #{names.inspect}"
    end

    if expected_values
      values = result.map do |item|
        if item.is_a?(String)
          item
        elsif item.respond_to?(:text)
          item.text
        else
          item.to_s
        end
      end
      expect(values).to eq(expected_values),
        "Expected values #{expected_values.inspect}, got #{values.inspect}"
    end

    if expected_types
      types = result.map(&:class)
      expect(types).to eq(expected_types),
        "Expected types #{expected_types.inspect}, got #{types.inspect}"
    end

    result
  end

  # Quick assertion for XPath result count
  def assert_xpath_count(node, expression, count)
    result = node.xpath(expression)
    expect(result.size).to eq(count),
      "XPath '#{expression}' expected #{count} results, got #{result.size}"
  end

  # Quick assertion for XPath result element names
  def assert_xpath_names(node, expression, *names)
    result = node.xpath(expression)
    actual = result.map { |e| e.respond_to?(:name) ? e.name : nil }.compact
    expect(actual).to eq(names),
      "XPath '#{expression}' expected names #{names.inspect}, got #{actual.inspect}"
  end

  # Quick assertion for XPath result returning specific element
  def assert_xpath_element(node, expression, expected_name)
    result = node.xpath(expression)
    expect(result).not_to be_empty, "XPath '#{expression}' returned no results"
    expect(result.first).to be_a(Taurus::Element)
    expect(result.first.name).to eq(expected_name)
  end

  # Quick assertion for XPath returning empty result
  def assert_xpath_empty(node, expression)
    result = node.xpath(expression)
    expect(result).to be_empty,
      "XPath '#{expression}' expected empty result, got #{result.size} items"
  end

  # Helper to create a simple XML document for testing
  def create_test_document(xml_string = nil)
    xml_string ||= <<~XML
      <root>
        <child id="1">First</child>
        <child id="2">Second</child>
      </root>
    XML
    parse(xml_string)
  end

  # Helper to navigate to a specific element by path
  def navigate_to(root, path)
    parts = path.split('/')
    current = root
    
    parts.each do |part|
      next if part.empty?
      current = current.nodes.find { |n| n.is_a?(Taurus::Element) && n.name == part }
      break if current.nil?
    end
    
    current
  end

  # Helper to verify element hierarchy
  def verify_parent_child(parent, child)
    expect(child.parent).to eq(parent),
      "Expected #{child.name} to have #{parent.name} as parent"
    expect(parent.nodes).to include(child),
      "Expected #{parent.name} to contain #{child.name} in nodes"
  end
end

RSpec.configure do |config|
  config.include XPathHelpers
end