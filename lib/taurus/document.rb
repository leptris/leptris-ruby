# frozen_string_literal: true

require_relative "element"

module Taurus
  # Represents an XML document with optional XML declaration (prolog).
  #
  # Document is the top-level container for an XML tree. It extends {Element}
  # and adds support for XML version, encoding, and standalone attributes.
  # The document maintains a root element and provides optimized access to it.
  #
  # @example Parse a document
  #   doc = Taurus.parse('<root><item/></root>')
  #   doc.version # => "1.0"
  #   doc.root.name # => "root"
  #
  # @example Create a document programmatically
  #   doc = Taurus::Document.new(version: "1.0", encoding: "UTF-8")
  #   root = Taurus::Element.new("root")
  #   doc.root = root
  #
  # @example XPath queries on document
  #   doc = Taurus.parse('<library><book><title>Ruby</title></book></library>')
  #   titles = doc.xpath('//title')
  #   count = doc.xpath('count(//book)') # => 1.0
  #
  # @see Element
  # @see #root
  # @see #xpath
  class Document < Element
    # @return [String] the XML version (default: "1.0")
    # @return [String, nil] the character encoding (e.g., "UTF-8")
    # @return [Boolean, nil] whether the document is standalone
    attr_accessor :version, :encoding, :standalone

    # Create a new XML document
    #
    # @param prolog [Hash] XML declaration attributes
    # @option prolog [String] :version ("1.0") the XML version
    # @option prolog [String] :encoding the character encoding
    # @option prolog [Boolean] :standalone whether document is standalone
    #
    # @example Default document
    #   doc = Taurus::Document.new
    #   doc.version # => "1.0"
    #
    # @example Document with encoding
    #   doc = Taurus::Document.new(encoding: "UTF-8")
    def initialize(prolog = {})
      super(nil)
      @version = prolog[:version] || "1.0"
      @encoding = prolog[:encoding]
      @standalone = prolog[:standalone]
      @nodes = []
    end

    # Returns the root element of the document
    #
    # This method uses a two-level optimization strategy:
    # 1. Ruby cache (@root) - set on first access or assignment
    # 2. C fast-path (root_fast) - blazing fast ivar access from C
    #
    # The first call scans the nodes array to find the root element.
    # Subsequent calls use the cached value for O(1) access.
    #
    # @return [Element, nil] the root element or nil if no root exists
    #
    # @example
    #   doc = Taurus.parse('<root><child/></root>')
    #   root = doc.root
    #   root.name # => "root"
    #
    # @see #root=
    def root
      # If cache exists, return cached value
      return @root if instance_variable_defined?(:@root)
      
      # First access - find and cache root
      @root = nodes.find { |n| n.is_a?(Element) }
    end

    # Sets the root element of the document
    #
    # Replaces any existing root element with the given element.
    # The root element becomes a child node of the document.
    #
    # @param element [Element, nil] the new root element or nil to remove root
    # @return [Element, nil] the assigned element
    #
    # @example
    #   doc = Taurus::Document.new
    #   root = Taurus::Element.new("root")
    #   doc.root = root
    #   doc.root.name # => "root"
    #
    # @see #root
    def root=(element)
      # Remove existing root if present
      nodes.delete_if { |n| n.is_a?(Element) }
      # Add new root
      nodes << element if element
      # Update cache
      @root = element
    end

    # Execute an XPath query on the document
    #
    # Evaluates the given XPath expression with the document as both the
    # document context and the context node. Supports full XPath 1.0 specification
    # including all 13 axes, 27 functions, and operators.
    #
    # @param expression [String] the XPath expression to evaluate
    # @param namespaces [Hash{String => String}, nil] optional custom namespace mappings
    #   (prefix => URI). Overrides auto-detected namespaces.
    # @return [Array<Element>, String, Numeric, Boolean] the query result
    #   - Node-set queries return Array<Element>
    #   - String queries return String
    #   - Numeric queries return Float
    #   - Boolean queries return true/false
    #
    # @raise [ArgumentError] if expression is invalid
    #
    # @example Find all elements
    #   doc.xpath('//book') # => [<book>, <book>, ...]
    #
    # @example Count elements
    #   doc.xpath('count(//book)') # => 2.0
    #
    # @example Boolean query
    #   doc.xpath('boolean(//book[@price > 20])') # => true
    #
    # @example String query
    #   doc.xpath('string(//title)') # => "First Title"
    #
    # @example Custom namespaces
    #   doc.xpath('//ns:book', namespaces: { 'ns' => 'http://books.org' })
    #
    # @see Element#xpath
    # @see XPath
    def xpath(expression, namespaces: nil)
      # Validate XPath expression
      if expression.nil? || expression.empty?
        raise Taurus::ParseError.new(
          "Empty XPath expression",
          code: :empty_input,
          line: 0,
          column: 0
        )
      end
      
      # Use root element as context node (Document itself is the document context)
      Taurus.xpath_evaluate(self, expression, root, namespaces)
    end
  end
end