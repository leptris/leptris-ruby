# frozen_string_literal: true

module Taurus
  # A Hash subclass that allows transparent access with both string and symbol keys.
  #
  # AttributesHash is used to store XML element attributes, providing convenient
  # access regardless of whether you use strings or symbols as keys. All keys are
  # internally stored as symbols for consistency and performance.
  #
  # @example Access with symbols
  #   elem = doc.root
  #   elem.attributes[:id]   # => "123"
  #   elem[:id]              # => "123" (shorthand)
  #
  # @example Access with strings
  #   elem.attributes["id"]  # => "123" (converted to symbol)
  #   elem["id"]             # => "123" (shorthand)
  #
  # @example Setting attributes
  #   elem[:class] = "important"    # stored as :class
  #   elem["data-id"] = "456"       # stored as :"data-id"
  #
  # @example Best practice for performance
  #   # Prefer symbols for ~90% better performance
  #   elem[:id]              # Fast path
  #   elem["id"]             # Slower (needs conversion)
  #
  # @see Element#attributes
  # @see Element#[]
  # @see Element#[]=
  class AttributesHash < Hash
    # Retrieve a value by key, trying symbol and string variants
    #
    # Attempts to find the value using three strategies:
    # 1. Direct lookup with the given key
    # 2. Lookup with key converted to symbol
    # 3. Lookup with key converted to string
    #
    # @param key [String, Symbol] the attribute name
    # @return [String, nil] the attribute value or nil if not found
    #
    # @example
    #   attrs = AttributesHash.new
    #   attrs[:id] = "123"
    #   attrs[:id]     # => "123"
    #   attrs["id"]    # => "123"
    #   attrs[:other]  # => nil
    def [](key)
      super(key) || super(key.to_sym) || super(key.to_s)
    end

    # Set a value by key, always storing as a symbol
    #
    # All keys are normalized to symbols for consistent internal storage
    # and optimal performance.
    #
    # @param key [String, Symbol] the attribute name
    # @param value [String] the attribute value
    # @return [String] the value that was set
    #
    # @example
    #   attrs = AttributesHash.new
    #   attrs["id"] = "123"        # stored as :id
    #   attrs[:class] = "widget"   # stored as :class
    def []=(key, value)
      super(key.to_sym, value)
    end

    # Check if a key exists, trying symbol and string variants
    #
    # @param key [String, Symbol] the attribute name to check
    # @return [Boolean] true if the key exists
    #
    # @example
    #   attrs = AttributesHash.new
    #   attrs[:id] = "123"
    #   attrs.key?(:id)    # => true
    #   attrs.key?("id")   # => true
    #   attrs.key?(:name)  # => false
    def key?(key)
      super(key) || super(key.to_sym) || super(key.to_s)
    end

    alias has_key? key?
  end
end