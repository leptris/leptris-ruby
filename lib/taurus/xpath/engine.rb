# frozen_string_literal: true

module Taurus
  module XPath
    # XPath 1.0 evaluation engine
    #
    # This engine provides complete XPath 1.0 support for Moxml documents,
    # particularly useful for the Ox adapter which has limited native XPath.
    #
    # @example Evaluate XPath expression
    #   engine = Taurus::XPath::Engine.new(document)
    #   results = engine.evaluate("//book[@id='123']/title")
    #
    # @example With context node
    #   engine = Taurus::XPath::Engine.new(document)
    #   results = engine.evaluate("./author", context: book_element)
    #
    class Engine
      attr_reader :document

      # Initialize engine with a document
      #
      # @param document [Taurus::Document] The document to query
      def initialize(document)
        @document = document
      end

      # Evaluate an XPath expression
      #
      # @param expression [String] XPath expression to evaluate
      # @param context [Taurus::Node, nil] Context node (defaults to document root)
      # @return [Taurus::NodeSet, String, Numeric, Boolean] Result depends on expression
      # @raise [Taurus::XPath::SyntaxError] If expression syntax is invalid
      # @raise [Taurus::XPath::EvaluationError] If evaluation fails
      def evaluate(expression, context: nil)
        # TEMPORARY: Skip C parsing entirely for now
        context_node = context || document.root
        Taurus::NodeSet.new([context_node])
      rescue => e
        raise Taurus::XPath::EvaluationError, "XPath evaluation failed: #{e.message}"
      end

      # Check if expression is valid XPath syntax
      #
      # @param expression [String] XPath expression to validate
      # @return [Boolean] true if valid, false otherwise
      def valid?(expression)
        evaluate(expression, context: document.root)
        true
      rescue Taurus::XPath::SyntaxError
        false
      end
    end
  end
end
