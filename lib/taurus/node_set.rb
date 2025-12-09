# frozen_string_literal: true

require 'set'

module Taurus
  # Collection of nodes returned by XPath queries.
  #
  # NodeSet provides an Enumerable interface to a collection of XML nodes.
  # It is typically returned by XPath queries and supports standard array-like
  # operations while maintaining the context of the query.
  #
  # @example Access nodes from XPath
  #   doc = Taurus.parse('<root><item/><item/></root>')
  #   items = doc.xpath('//item')
  #   items.size # => 2
  #   items.first # => <item>
  #
  # @example Iterate over nodes
  #   doc.xpath('//item').each do |item|
  #     puts item.name
  #   end
  #
  # @example Convert to array
  #   nodes = doc.xpath('//item').to_a
  #
  # @see Document#xpath
  # @see Element#xpath
  class NodeSet
    include Enumerable

    # @return [Array<Element>] the collection of nodes
    # @return [Element, Document, nil] the context node for the query
    attr_reader :nodes, :context

    # Create a new NodeSet
    #
    # @param nodes [Array<Element>, Element, nil] nodes to include in the set
    # @param context [Element, Document, nil] the context node for the query
    #
    # @example Create from array
    #   nodes = [elem1, elem2]
    #   node_set = Taurus::NodeSet.new(nodes)
    #
    # @example Create from single node
    #   node_set = Taurus::NodeSet.new(elem)
    def initialize(nodes = [], context = nil)
      @nodes = Array(nodes)
      @context = context
    end

    # Iterate over each node in the set
    #
    # @yieldparam node [Element] each node in the set
    # @return [Enumerator] if no block given
    #
    # @example
    #   node_set.each { |node| puts node.name }
    def each(&block)
      @nodes.each(&block)
    end

    # Return the number of nodes in the set
    #
    # @return [Integer] the number of nodes
    #
    # @example
    #   doc.xpath('//item').size # => 3
    def size
      @nodes.size
    end

    # Check if the node set is empty
    #
    # @return [Boolean] true if no nodes in set
    #
    # @example
    #   doc.xpath('//nonexistent').empty? # => true
    def empty?
      @nodes.empty?
    end

    # Return the first node in the set
    #
    # @return [Element, nil] the first node or nil if empty
    #
    # @example
    #   doc.xpath('//item').first # => <item>
    def first
      @nodes.first
    end

    # Return the last node in the set
    #
    # @return [Element, nil] the last node or nil if empty
    #
    # @example
    #   doc.xpath('//item').last # => <item>
    def last
      @nodes.last
    end

    # Access node by index
    #
    # @param index [Integer] the index (0-based)
    # @return [Element, nil] the node at index or nil
    #
    # @example
    #   nodes = doc.xpath('//item')
    #   nodes[0] # => first item
    #   nodes[1] # => second item
    def [](index)
      @nodes[index]
    end

    # Convert the node set to an array
    #
    # @return [Array<Element>] array of nodes
    #
    # @example
    #   doc.xpath('//item').to_a # => [<item>, <item>, ...]
    def to_a
      @nodes
    end

    # Remove duplicate nodes by object identity
    #
    # This method modifies the node set in-place to remove duplicate nodes
    # based on their native object identity. Useful when union operations
    # may produce duplicate references.
    #
    # @return [NodeSet] self
    #
    # @example
    #   node_set.uniq_by_native
    #   node_set.size # => reduced if duplicates removed
    def uniq_by_native
      # Remove duplicates by object identity
      seen = Set.new
      unique_nodes = []
      @nodes.each do |node|
        native = node.respond_to?(:native) ? node.native : node
        unless seen.include?(native)
          seen.add(native)
          unique_nodes << node
        end
      end
      @nodes = unique_nodes
      self
    end

    # Return a string representation of the node set
    #
    # @return [String] a debug-friendly representation
    #
    # @example
    #   node_set.inspect # => "#<Taurus::NodeSet:70123456 size=3>"
    def inspect
      "#<Taurus::NodeSet:#{object_id} size=#{size}>"
    end
  end
end
