# frozen_string_literal: true

module Taurus
  # Base class for all XML nodes in the document tree.
  #
  # Node provides the foundation for {Element}, {Document}, and other node types.
  # It maintains the node's value and parent relationship in the tree structure.
  #
  # @abstract Subclass and override methods to create specific node types
  #
  # @example Direct instantiation (typically not used directly)
  #   node = Taurus::Node.new("value")
  #   node.value # => "value"
  #
  # @see Element
  # @see Document
  class Node
    # @return [String, Symbol, nil] the node's value (name for elements, content for text)
    # @return [Element, nil] the parent element of this node
    attr_accessor :value, :parent

    # Create a new node with the given value
    #
    # @param value [String, Symbol, nil] the node's value
    #
    # @example
    #   node = Taurus::Node.new("content")
    def initialize(value)
      @value = value
      @parent = nil
    end

    # Check equality with another node based on value
    #
    # Two nodes are equal if they are both Node instances and have the same value.
    # Subclasses may override this to check additional attributes.
    #
    # @param other [Node] the node to compare with
    # @return [Boolean] true if nodes are equal
    #
    # @example
    #   node1 = Taurus::Node.new("test")
    #   node2 = Taurus::Node.new("test")
    #   node1 == node2 # => true
    def eql?(other)
      return false unless other.is_a?(Node)
      value == other.value
    end
    alias == eql?
  end
end