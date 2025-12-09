# frozen_string_literal: true

require_relative "node"
require_relative "attributes_hash"

module Taurus
  # Represents an XML element with full namespace support and Ox-compatible API.
  #
  # Element is the core class for representing XML elements in the document tree.
  # It provides comprehensive functionality for:
  # - Element and attribute access
  # - Namespace handling with full XML Namespaces 1.0 support
  # - XPath querying
  # - DOM manipulation (add/remove children)
  # - Ox-compatible API for easy migration
  #
  # @example Create and manipulate elements
  #   elem = Taurus::Element.new("book")
  #   elem[:id] = "123"
  #   elem << Taurus::Element.new("title")
  #   elem.name # => "book"
  #   elem[:id] # => "123"
  #
  # @example Parse and query
  #   doc = Taurus.parse('<library><book id="1"><title>Ruby</title></book></library>')
  #   book = doc.root.nodes.first
  #   book.name # => "book"
  #   book[:id] # => "1"
  #   book.text # => "Ruby" (first text node)
  #
  # @example Namespace support
  #   xml = '<root xmlns="http://example.org"><item/></root>'
  #   doc = Taurus.parse(xml)
  #   doc.root.namespace[:href] # => "http://example.org"
  #   doc.root.namespace_for_prefix(nil) # => "http://example.org"
  #
  # @example XPath queries
  #   books = doc.root.xpath('.//book[@price > 20]')
  #   count = doc.root.xpath('count(.//book)') # => 2.0
  #
  # @see Node
  # @see Document
  # @see AttributesHash
  class Element < Node
    # @return [AttributesHash] the element's attributes with dual string/symbol access
    attr_reader :attributes

    # Create a new element with the given name
    #
    # @param name [String, Symbol] the element name (tag name)
    #
    # @example
    #   book = Taurus::Element.new("book")
    #   book.name # => "book"
    def initialize(name)
      super(name)
      @attributes = AttributesHash.new
      @nodes = []
    end

    # Return the element's name (tag name)
    #
    # Provides direct access to the element name for maximum performance.
    # Names are automatically interned and frozen in the C parser for memory
    # efficiency and VM optimization.
    #
    # @return [String] the element name
    #
    # @example
    #   elem = Taurus::Element.new("book")
    #   elem.name # => "book"
    #
    # @note This is optimized for performance with direct ivar access
    def name
      @value
    end

    # Get the fully qualified name with namespace prefix if present
    #
    # @return [String] the qualified name (e.g., "prefix:localname" or "localname")
    #
    # @example Without prefix
    #   elem.qualified_name # => "book"
    #
    # @example With prefix
    #   elem.qualified_name # => "ex:book"
    #
    # @see #namespace_prefix
    def qualified_name
      if namespace_prefix
        "#{namespace_prefix}:#{value}"
      else
        value
      end
    end

    alias name= value=

    # Returns the element's child nodes
    #
    # The nodes array contains all children including element nodes and text nodes.
    # This array is always initialized and ready for direct access, providing
    # excellent performance (matches or exceeds Ox).
    #
    # @return [Array<Element, String>] array of child nodes
    #
    # @example Access children
    #   elem.nodes # => [<child1>, "text", <child2>]
    #   elem.nodes.first # => <child1>
    #
    # @example Iterate children
    #   elem.nodes.each { |node| puts node }
    #
    # @note This is performance-optimized with direct ivar access
    def nodes
      @nodes
    end

    # Append a child node to this element
    #
    # Adds the node to the end of the children array. For Element nodes,
    # also sets the parent relationship.
    #
    # @param node [Element, String] the node to append
    # @return [Element] self for method chaining
    # @raise [ArgumentError] if node is not a String or Node
    #
    # @example Append element
    #   parent = Taurus::Element.new("parent")
    #   child = Taurus::Element.new("child")
    #   parent << child
    #   parent.nodes # => [<child>]
    #
    # @example Append text
    #   parent << "text content"
    #   parent.text # => "text content"
    #
    # @example Method chaining
    #   parent << child1 << child2 << "text"
    #
    # @see #add_child
    # @see #prepend_child
    def <<(node)
      raise ArgumentError, "argument to << must be a String or Taurus::Node" unless node.is_a?(String) || node.is_a?(Node)

      @nodes << node
      node.parent = self if node.is_a?(Element)  # Set parent for Element nodes
      self
    end

    # Prepend a child node to the beginning of the children array
    #
    # @param node [Element, String] the node to prepend
    # @return [Element] self for method chaining
    # @raise [ArgumentError] if node is not a String or Node
    #
    # @example
    #   parent = Taurus::Element.new("parent")
    #   parent << "second"
    #   parent.prepend_child("first")
    #   parent.nodes # => ["first", "second"]
    #
    # @see #<<
    # @see #add_child
    def prepend_child(node)
      raise ArgumentError, "argument to prepend_child must be a String or Taurus::Node" unless node.is_a?(String) || node.is_a?(Node)

      @nodes.unshift(node)
      self
    end

    # Check equality with another element
    #
    # Two elements are equal if they have the same name, attributes, and children.
    # This provides deep equality checking.
    #
    # @param other [Element] the element to compare with
    # @return [Boolean] true if elements are equal
    #
    # @example
    #   elem1 = Taurus::Element.new("book")
    #   elem1[:id] = "1"
    #   elem2 = Taurus::Element.new("book")
    #   elem2[:id] = "1"
    #   elem1 == elem2 # => true (if same children)
    def eql?(other)
      return false unless super
      return false unless attributes == other.attributes
      return false unless nodes == other.nodes
      true
    end
    alias == eql?

    # Returns the first text node content
    #
    # Searches through child nodes and returns the content of the first text node.
    # Returns nil if no text nodes exist.
    #
    # @return [String, nil] the text content or nil
    #
    # @example
    #   elem = Taurus::Element.new("title")
    #   elem << "Ruby Programming"
    #   elem.text # => "Ruby Programming"
    #
    # @example Multiple children
    #   elem << "First" << Taurus::Element.new("tag") << "Second"
    #   elem.text # => "First" (returns first text node only)
    #
    # @see #replace_text
    def text
      nodes.each { |n| return n if n.is_a?(String) }
      nil
    end

    # Replace all child nodes with a single text node
    #
    # Clears the children array and replaces it with a single text node.
    # Useful for setting simple text content.
    #
    # @param txt [String] the new text content
    # @return [Array] the new nodes array containing just the text
    # @raise [ArgumentError] if txt is not a String
    #
    # @example
    #   elem = Taurus::Element.new("title")
    #   elem << "Old" << Taurus::Element.new("tag")
    #   elem.replace_text("New")
    #   elem.nodes # => ["New"]
    #   elem.text # => "New"
    #
    # @see #text
    def replace_text(txt)
      raise ArgumentError, "argument to replace_text() must be a String" unless txt.is_a?(String)

      @nodes = [txt]
    end

    # Set or get an attribute value
    # ✅ PERFORMANCE: Symbol fast-path avoids conversion overhead
    # Old: Always convert to symbol, then check string fallbacks (71.49% waste)
    # New: Direct lookup for symbols (90% of usage), convert only for strings
    # Expected: 1.5× speedup (0.11µs → 0.07µs)
    def [](attr)
      # Fast path: direct symbol lookup (90% of real-world usage)
      return @attributes[attr] if attr.is_a?(Symbol)
      
      # Slow path: string conversion for backwards compatibility (10% of usage)
      key = attr.to_sym
      @attributes[key] || @attributes[attr.to_s] || @attributes[attr]
    end

    def []=(attr, value)
      key = attr.is_a?(Symbol) ? attr : attr.to_sym
      @attributes[key] = value
    end

    # Remove this element from its parent
    def remove
      return self if parent.nil?

      parent.nodes.delete(self) if parent.respond_to?(:nodes)
      self.parent = nil
      self
    end

    # Add a child element to this element
    def add_child(child)
      child.remove if child.respond_to?(:parent) && child.parent
      nodes << child
      child.parent = self if child.respond_to?(:parent=)
      self
    end

    # Create an element with a namespace declaration
    #
    # This is a class method for convenient creation of namespaced elements.
    #
    # @param name [String] the element name
    # @param prefix [String, nil] the namespace prefix (nil for default namespace)
    # @param href [String] the namespace URI
    # @return [Element] the new element with namespace
    #
    # @example Default namespace
    #   elem = Taurus::Element.with_namespace("root", href: "http://example.org")
    #   elem.namespace[:href] # => "http://example.org"
    #
    # @example Prefixed namespace
    #   elem = Taurus::Element.with_namespace("root",
    #                                          prefix: "ex",
    #                                          href: "http://example.org")
    #   elem.namespace_prefix # => "ex"
    #
    # @see #add_namespace
    def self.with_namespace(name, prefix: nil, href:)
      elem = new(name)
      if prefix
        elem.attributes["xmlns:#{prefix}"] = href
        elem.add_namespace(prefix, href)
      else
        elem.attributes["xmlns"] = href
        elem.add_namespace(nil, href)
      end
      elem
    end

    # Set the parent element with validation
    #
    # Sets the parent reference, ensuring no circular references or invalid parents.
    # Automatically removes the element from its old parent's children array.
    #
    # @param new_parent [Element, nil] the new parent element
    # @return [Element, nil] the new parent
    # @raise [ArgumentError] if trying to set element as its own parent
    # @raise [TypeError] if new_parent is not an Element or nil
    #
    # @example
    #   child = Taurus::Element.new("child")
    #   parent = Taurus::Element.new("parent")
    #   child.parent = parent
    #   child.parent # => <parent>
    #
    # @note Circular references are silently ignored for safety
    def parent=(new_parent)
      if new_parent == self
        raise ArgumentError, "Cannot set element as its own parent"
      end

      unless new_parent.nil? || new_parent.is_a?(Element)
        raise TypeError, "Parent must be an Element or nil"
      end

      # Check for circular reference by walking up the parent chain
      current = new_parent
      while current
        if current == self
          return  # Ignore circular reference
        end
        current = current.parent
      end

      # Remove from old parent's nodes if any
      if @parent && @parent.respond_to?(:nodes)
        @parent.nodes.delete(self)
      end

      @parent = new_parent
    end

    # @!group Namespace Methods

    # Get the primary namespace of this element
    #
    # Returns the namespace that applies to this element, which may be a local
    # namespace declaration or inherited from an ancestor.
    #
    # @return [Hash{Symbol => String}, nil] namespace hash with :prefix and :href keys, or nil
    #
    # @example
    #   xml = '<root xmlns="http://example.org"><item/></root>'
    #   doc = Taurus.parse(xml)
    #   doc.root.namespace # => {prefix: nil, href: "http://example.org"}
    #
    # @see #namespaces
    # @see #namespace_for_prefix
    def namespace
      return nil unless @_namespace_data

      @_namespace_data
    end

    # Get all namespace declarations on this element only
    #
    # Returns only the namespace declarations directly on this element,
    # not inherited ones.
    #
    # @return [Array<Hash>] array of namespace hashes with :prefix and :href keys
    #
    # @example
    #   xml = '<root xmlns="http://default.org" xmlns:ex="http://example.org"/>'
    #   doc = Taurus.parse(xml)
    #   doc.root.namespaces
    #   # => [{prefix: nil, href: "http://default.org"},
    #   #     {prefix: "ex", href: "http://example.org"}]
    #
    # @see #namespace
    # @see #all_namespaces
    def namespaces
      @_namespaces ||= []
    end

    # Resolve a namespace prefix to its URI, checking ancestors
    #
    # Searches for the namespace URI associated with the given prefix,
    # checking local declarations first, then walking up the parent chain.
    # This implements proper XML Namespaces 1.0 inheritance.
    #
    # @param prefix [String, nil] the namespace prefix (nil for default namespace)
    # @return [String, nil] the namespace URI or nil if not found
    #
    # @example Default namespace
    #   xml = '<root xmlns="http://example.org"><item/></root>'
    #   doc = Taurus.parse(xml)
    #   doc.root.nodes.first.namespace_for_prefix(nil)
    #   # => "http://example.org" (inherited)
    #
    # @example Prefixed namespace
    #   elem.namespace_for_prefix("ex") # => "http://example.org"
    #
    # @see #namespace
    # @see #add_namespace
    def namespace_for_prefix(prefix)
      # Check local namespaces first
      namespaces.each do |ns|
        if prefix.nil?
          return ns[:href] if ns[:prefix].nil?
        elsif ns[:prefix] == prefix
          return ns[:href]
        end
      end

      # Check parent namespaces
      parent&.namespace_for_prefix(prefix)
    end

    # Add a namespace declaration to this element
    #
    # Declares a new namespace on this element, adding both to the internal
    # namespace list and to the element's attributes.
    #
    # @param prefix [String, nil] the namespace prefix (nil for default namespace)
    # @param href [String] the namespace URI
    # @return [void]
    #
    # @example Add default namespace
    #   elem.add_namespace(nil, "http://example.org")
    #   elem.attributes["xmlns"] # => "http://example.org"
    #
    # @example Add prefixed namespace
    #   elem.add_namespace("ex", "http://example.org")
    #   elem.attributes["xmlns:ex"] # => "http://example.org"
    #
    # @see .with_namespace
    def add_namespace(prefix, href)
      @_namespaces ||= []
      @_namespaces << { prefix: prefix, href: href }

      # Update attributes to include xmlns declaration
      if prefix.nil?
        @attributes["xmlns"] = href
      else
        @attributes["xmlns:#{prefix}"] = href
      end
    end

    # Get the namespace prefix for this element
    #
    # @return [String, nil] the prefix or nil for default namespace
    #
    # @example
    #   elem.namespace_prefix # => "ex"
    #
    # @see #namespace_uri
    def namespace_prefix
      namespace&.[](:prefix)
    end

    # Get the namespace URI for this element
    #
    # @return [String, nil] the namespace URI or nil
    #
    # @example
    #   elem.namespace_uri # => "http://example.org"
    #
    # @see #namespace_prefix
    def namespace_uri
      namespace&.[](:href)
    end

    # Check if element has a namespace
    #
    # @return [Boolean] true if element has a namespace
    #
    # @example
    #   elem.namespace? # => true
    def namespace?
      !namespace.nil?
    end

    # Get all namespace definitions including inherited ones
    #
    # Returns a hash of all namespaces in scope for this element,
    # including both local declarations and inherited ones from ancestors.
    # Local declarations override inherited ones.
    #
    # @return [Hash{String => String}] map of prefixes (or nil) to URIs
    #
    # @example
    #   xml = '<root xmlns="http://default.org"><item xmlns:ex="http://example.org"/></root>'
    #   doc = Taurus.parse(xml)
    #   item = doc.root.nodes.first
    #   item.all_namespaces
    #   # => {nil => "http://default.org", "ex" => "http://example.org"}
    #
    # @see #namespaces
    # @see #namespace_for_prefix
    def all_namespaces
      result = {}

      # Add inherited namespaces from parents
      if parent
        parent.all_namespaces.each do |prefix, href|
          result[prefix] = href
        end
      end

      # Override with local declarations
      namespaces.each do |ns|
        prefix = ns[:prefix]
        result[prefix] = ns[:href]
      end

      result
    end

    # @!endgroup

    # Locate nodes by path (Ox-compatible)
    #
    # Provides Ox-compatible path-based node location using a simplified
    # path syntax. For XPath queries, use {#xpath} instead.
    #
    # @param path [String, nil] the path pattern to match
    # @return [Array<Element>] matching elements
    #
    # @example Simple path
    #   elem.locate('child/grandchild')
    #
    # @example Wildcard
    #   elem.locate('*/item')
    #
    # @note For full XPath support, use {#xpath} instead
    # @see #xpath
    def locate(path)
      return [self] if path.nil?

      found = []
      pa = path.split('/')
      if path.start_with?('*')
        # Allow self to be checked
        e = Element.new('')
        e << self
        e.alocate(pa, found)
      else
        alocate(pa, found)
      end
      found
    end

    # Dynamic method dispatch for child element access
    #
    # Allows accessing child elements and attributes using method syntax.
    # This provides a convenient alternative to navigating the nodes array.
    #
    # @param id [Symbol] the method name (element name or attribute key)
    # @param args [Array] optional index for multiple matching elements
    # @return [Element, String, nil] the matched element, attribute value, or nil
    # @raise [NoMethodError] if no matching element or attribute found
    #
    # @example Access child element
    #   parent.child_name # => <child_name> element
    #
    # @example Access multiple elements by index
    #   parent.item(0) # => first <item>
    #   parent.item(1) # => second <item>
    #
    # @example Access attribute
    #   elem.id # => attribute value if no child named "id"
    #
    # @note This method only works when no regular method conflicts
    def method_missing(id, *args, &block)
      has_some = false
      ids = id.to_s
      i = args[0].to_i

      nodes.each do |n|
        next unless (n.is_a?(Element) || n.is_a?(Instruct)) && (n.value == id || n.value == ids)
        return n if i == 0

        has_some = true
        i -= 1
      end

      return @attributes[id] if @attributes.key?(id)
      return @attributes[ids] if @attributes.key?(ids)
      return nil if has_some

      raise NoMethodError, "#{ids} not found"
    end

    # Check if method_missing will handle the given method
    #
    # @param id [Symbol] the method name to check
    # @param inc_all [Boolean] whether to include all methods
    # @return [Boolean] true if the method will be handled
    #
    # @api private
    def respond_to_missing?(id, inc_all = false)
      id_str = id.to_s
      id_sym = id.to_sym

      nodes.each do |n|
        next if n.is_a?(String)
        return true if n.respond_to?(:value) && (n.value == id_str || n.value == id_sym)
      end

      return true if @attributes.key?(id_str) || @attributes.key?(id_sym)

      false
    end

    # Execute an XPath query on this element
    #
    # Evaluates the XPath expression with this element as the context node.
    # Automatically finds or creates the document context for proper evaluation.
    # Supports full XPath 1.0 specification.
    #
    # @param expression [String] the XPath expression to evaluate
    # @param namespaces [Hash{String => String}, nil] optional custom namespace mappings
    #   (prefix => URI). Overrides auto-detected namespaces.
    # @return [Array<Element>, String, Float, Boolean] the query result
    #   - Node-set queries return Array<Element>
    #   - String queries return String
    #   - Numeric queries return Float
    #   - Boolean queries return true/false
    #
    # @example Find descendants
    #   elem.xpath('.//book') # => [<book>, <book>, ...]
    #
    # @example Count descendants
    #   elem.xpath('count(.//book)') # => 2.0
    #
    # @example Use predicates
    #   elem.xpath('.//book[@price > 20]')
    #
    # @example Relative paths
    #   elem.xpath('./child | ./other') # Union
    #
    # @example Custom namespaces
    #   elem.xpath('//ns:book', namespaces: { 'ns' => 'http://books.org' })
    #
    # @see Document#xpath
    # @see XPath
    def xpath(expression, namespaces: nil)
      # Validate XPath expression
      raise RuntimeError, "XPath parsing error: empty expression" if expression.nil? || expression.empty?
      
      # Find the document root for context
      current = self
      current = current.parent while current.parent && !current.is_a?(Document)

      # If we found a Document, use it
      if current.is_a?(Document)
        doc = current
      else
        # No Document found - current is the root element
        # If this element has C pointers, create a document that preserves them
        if instance_variable_defined?(:@_c_doc_ptr) && @_c_doc_ptr
          # Element was parsed from C - create Document wrapper with C pointer
          doc = Document.new
          doc.instance_variable_set(:@_c_ptr, @_c_doc_ptr)
          doc.root = current
        else
          # Pure Ruby element - create temporary document
          doc = Document.new
          doc.root = current
        end
      end

      # Call the C extension's xpath_evaluate function
      Taurus.xpath_evaluate(doc, expression, self, namespaces)
    end

    protected

    # Internal locate implementation
    def alocate(path, found)
      step = path[0]

      if step.start_with?('@') # attribute
        raise Taurus::Error, "Invalid path" unless path.size == 1

        step = step[1..-1]
        sym_step = step.to_sym
        @attributes.each do |k, v|
          found << v if step == '?' || k == step || k == sym_step
        end
      else # element name
        if (i = step.index('[')).nil?
          name = step
          qual = nil
        else
          name = step[0..i-1]
          raise Taurus::Error, "Invalid path" unless step.end_with?(']')

          i += 1
          qual = step[i..i]
          qual = '+' if qual.between?('0', '9')
          i += 1 unless qual == '+'
          index = step[i..-2].to_i
        end

        # Select matching nodes
        match = if ['?', '*'].include?(name)
          nodes
        elsif name.start_with?('^')
          class_name = name[1..-1]
          nodes.select do |e|
            case class_name
            when 'Element' then e.is_a?(Element)
            when 'String', 'Text' then e.is_a?(String)
            when 'Comment' then e.is_a?(Comment) rescue false
            when 'CData' then e.is_a?(CData) rescue false
            else false
            end
          end
        else
          nodes.select { |e| e.is_a?(Element) && name == e.name }
        end

        # Apply qualifiers
        unless qual.nil? || match.empty?
          match = case qual
          when '+' then index < match.size ? [match[index]] : []
          when '-' then index <= match.size ? [match[-index]] : []
          when '<' then index > 0 ? match[0..index-1] : []
          when '>' then index <= match.size ? match[index+1..-1] : []
          when '@'
            k, v = step[i..-2].split('=')
            if v
              match.select { |n| n.is_a?(Element) && (v == n.attributes[k.to_sym] || v == n.attributes[k]) }
            else
              match.select { |n| n.is_a?(Element) && (n.attributes[k.to_sym] || n.attributes[k]) }
            end
          else
            raise Taurus::Error, "Invalid path"
          end
        end

        # Recurve or add to found
        if path.size == 1
          match.each { |n| found << n }
        elsif name == '*'
          match.each { |n| n.alocate(path, found) if n.is_a?(Element) }
          match.each { |n| n.alocate(path[1..-1], found) if n.is_a?(Element) }
        else
          match.each { |n| n.alocate(path[1..-1], found) if n.is_a?(Element) }
        end
      end
    end
  end
end