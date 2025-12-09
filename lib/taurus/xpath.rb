# frozen_string_literal: true

module Taurus
  # XPath 1.0 query engine providing full W3C specification compliance.
  #
  # The XPath module provides low-level access to the XPath engine's tokenizer,
  # parser, and evaluator. For most use cases, you should use the high-level
  # {Document#xpath} and {Element#xpath} methods instead.
  #
  # @example High-level usage (recommended)
  #   doc = Taurus.parse(xml)
  #   results = doc.xpath('//book[@price > 20]')
  #
  # @example Low-level tokenization
  #   tokens = Taurus::XPath.tokenize('//book')
  #   tokens # => [{type: :slash_slash, value: '//', ...}, ...]
  #
  # @example Low-level parsing
  #   ast = Taurus::XPath.parse('//book[1]')
  #   ast # => {type: :path, ...}
  #
  # @example Low-level evaluation
  #   result = Taurus::XPath.evaluate(doc, '//book', doc.root)
  #
  # == XPath 1.0 Features
  #
  # The engine implements the complete XPath 1.0 specification:
  #
  # === All 13 Axes
  # - child, descendant, descendant-or-self
  # - parent, ancestor, ancestor-or-self
  # - self, following-sibling, preceding-sibling
  # - following, preceding, attribute, namespace
  #
  # === All 27 Functions
  # - String: string(), concat(), starts-with(), contains(), substring(),
  #   string-length(), normalize-space(), translate(), substring-before(),
  #   substring-after()
  # - Boolean: boolean(), not(), true(), false(), lang()
  # - Number: number(), sum(), floor(), ceiling(), round()
  # - Node-set: count(), id(), last(), position(), local-name(),
  #   namespace-uri(), name()
  #
  # === All Operators
  # - Logical: or, and
  # - Equality: =, !=
  # - Relational: <, <=, >, >=
  # - Arithmetic: +, -, *, div, mod
  # - Union: |
  #
  # === Predicates
  # - Position: [1], [N], [last()]
  # - Boolean: [@attr], [element], [expression]
  # - Comparison: [@price > 20], [@stock >= 5]
  #
  # @see Document#xpath
  # @see Element#xpath
  # @see https://www.w3.org/TR/1999/REC-xpath-19991116/ XPath 1.0 Specification
  module XPath
    class << self
      # Tokenize an XPath expression into a stream of tokens
      #
      # Breaks down an XPath expression into its constituent tokens for parsing.
      # This is the first stage of XPath processing. Most users should use
      # {Document#xpath} instead.
      #
      # @param expression [String] the XPath expression to tokenize
      # @return [Array<Hash>] array of token hashes with :type, :value, :line, :column
      #
      # @example Tokenize a simple path
      #   tokens = Taurus::XPath.tokenize('//book')
      #   tokens[0] # => {type: :slash_slash, value: '//', line: 1, column: 0}
      #   tokens[1] # => {type: :name, value: 'book', line: 1, column: 2}
      #
      # @example Tokenize with predicates
      #   tokens = Taurus::XPath.tokenize('//book[@id="1"]')
      #   # Returns tokens for path, predicate, attribute, equality, string
      #
      # @see .parse
      def tokenize(expression)
        Taurus.xpath_tokenize(expression)
      end

      # Parse an XPath expression into an Abstract Syntax Tree (AST)
      #
      # Converts a tokenized XPath expression into a tree structure representing
      # its logical structure. This is the second stage of XPath processing.
      # Most users should use {Document#xpath} instead.
      #
      # The AST is cached globally, so repeated calls with the same expression
      # are extremely fast (O(1) hash lookup).
      #
      # @param expression [String] the XPath expression to parse
      # @return [Hash] AST representation as a nested hash structure
      #
      # @example Parse a simple path
      #   ast = Taurus::XPath.parse('//book')
      #   ast[:type] # => :path
      #
      # @example Parse with functions
      #   ast = Taurus::XPath.parse('count(//book)')
      #   ast[:type] # => :function_call
      #   ast[:name] # => 'count'
      #
      # @see .tokenize
      # @see .evaluate
      def parse(expression)
        Taurus.xpath_parse(expression)
      end

      # Evaluate an XPath expression against a document
      #
      # Executes the XPath query and returns the result. This is the third and
      # final stage of XPath processing. Most users should use {Document#xpath}
      # or {Element#xpath} instead.
      #
      # @param document [Document] the document to query
      # @param expression [String] the XPath expression to evaluate
      # @param context_node [Element, Document, nil] the starting node for relative queries
      #   (default: document root)
      # @return [Array<Element>, String, Float, Boolean] the evaluation result
      #   - Node-set queries return Array<Element>
      #   - String queries return String
      #   - Numeric queries return Float
      #   - Boolean queries return true or false
      #
      # @raise [ArgumentError] if expression is invalid
      #
      # @example Evaluate to node-set
      #   nodes = Taurus::XPath.evaluate(doc, '//book', doc.root)
      #   nodes # => [<book>, <book>, ...]
      #
      # @example Evaluate to number
      #   count = Taurus::XPath.evaluate(doc, 'count(//book)')
      #   count # => 2.0
      #
      # @example Evaluate to boolean
      #   has_books = Taurus::XPath.evaluate(doc, 'boolean(//book)')
      #   has_books # => true
      #
      # @example Evaluate with context node
      #   item = doc.root.nodes.first
      #   children = Taurus::XPath.evaluate(doc, './child::*', item)
      #
      # @see Document#xpath
      # @see Element#xpath
      def evaluate(document, expression, context_node = nil)
        Taurus.xpath_evaluate(document, expression, context_node)
      end
    end
  end
end
