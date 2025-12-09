# frozen_string_literal: true

require_relative 'library'
require_relative 'types'
require_relative 'memory'
require_relative 'errors'

module Taurus
  module FFI
    # Bridge between C pointers and Ruby objects
    # Converts taurus_document/taurus_element pointers to Ruby Document/Element instances
    module Bridge
      class << self
        # Convert a taurus_document pointer to a Ruby Document object
        # @param doc_ptr [FFI::Pointer] the document pointer from C (wrapped in AutoPointer)
        # @return [Document] the Ruby Document object
        def document_from_ptr(doc_ptr)
          return nil if doc_ptr.nil? || doc_ptr.null?

          # Get encoding from C
          encoding_str = Taurus::FFI.taurus_document_encoding(doc_ptr)

          # Create Ruby Document with prolog
          doc = Document.new(
            version: "1.0",
            encoding: encoding_str
          )

          # CRITICAL: Store C pointer for XPath evaluation
          # The AutoPointer will handle cleanup when Ruby object is GC'd
          doc.instance_variable_set(:@_c_ptr, doc_ptr)

          # Get root element
          root_ptr = Taurus::FFI.taurus_document_root(doc_ptr)
          if root_ptr && !root_ptr.null?
            root_elem = element_from_ptr(root_ptr, doc_ptr)
            doc.root = root_elem if root_elem
          end

          doc
        end

        # Convert a taurus_element pointer to a Ruby Element object
        # @param elem_ptr [FFI::Pointer] the element pointer from C
        # @param doc_ptr [FFI::Pointer] the document pointer (for XPath context, optional)
        # @return [Element] the Ruby Element object
        def element_from_ptr(elem_ptr, doc_ptr = nil)
          return nil if elem_ptr.nil? || elem_ptr.null?

          # Safety check: detect attribute nodes before calling C functions
          # Attribute nodes have node_type (int, value 1) as first 4 bytes
          # Element nodes have name pointer (8 bytes) as first field
          begin
            first_bytes = elem_ptr.read_bytes(4)
            first_int = first_bytes.unpack1('L')  # Little-endian uint32
          rescue => e
            # If we can't read the pointer safely, it's invalid
            warn "Warning: Cannot read pointer in element_from_ptr: #{e.message}" if $DEBUG
            return nil
          end

          # If first 4 bytes == 1, it's TAURUS_NODE_ATTRIBUTE
          return nil if first_int == 1

          # Get element name and freeze it (string interning optimization)
          begin
            name = Taurus::FFI.taurus_element_name(elem_ptr)
            return nil unless name
            name = name.freeze
          rescue => e
            # Pointer is not a valid element
            warn "Warning: Invalid element pointer in element_from_ptr: #{e.message}" if $DEBUG
            return nil
          end

          # Create Ruby Element
          elem = Element.new(name)

          # CRITICAL: Store C pointers for XPath evaluation
          elem.instance_variable_set(:@_c_ptr, elem_ptr)
          elem.instance_variable_set(:@_c_doc_ptr, doc_ptr) if doc_ptr

          # Get text content (for text nodes)
          text = Taurus::FFI.taurus_element_text(elem_ptr)
          if text && !text.empty?
            elem.instance_variable_set(:@_text_content, text)
          end

          # Set namespace data if present
          ns_uri = Taurus::FFI.taurus_element_namespace(elem_ptr)
          ns_prefix = Taurus::FFI.taurus_element_prefix(elem_ptr)

          if ns_uri && !ns_uri.empty?
            elem.instance_variable_set(:@_namespace_data, {
              prefix: (ns_prefix && !ns_prefix.empty?) ? ns_prefix : nil,
              href: ns_uri
            })
          end

          # Load attributes
          load_attributes(elem_ptr, elem)

          # Load namespace declarations
          load_namespaces(elem_ptr, elem)

          # Load children
          load_children(elem_ptr, elem, doc_ptr)

          elem
        end

        # Load attributes from C element to Ruby element
        # @param elem_ptr [FFI::Pointer] the C element pointer
        # @param elem [Element] the Ruby element
        # @return [void]
        def load_attributes(elem_ptr, elem)
          count = Taurus::FFI.taurus_element_attribute_count(elem_ptr)

          count.times do |i|
            begin
              attr_ptr = Taurus::FFI.taurus_element_attribute(elem_ptr, i)
              next if attr_ptr.nil? || attr_ptr.null?

              name = Taurus::FFI.taurus_attribute_name(attr_ptr)
              value = Taurus::FFI.taurus_attribute_value(attr_ptr)

              elem.attributes[name.to_sym] = value if name && value
            rescue => e
              # Skip invalid attribute pointers
              warn "Warning: Failed to load attribute #{i}: #{e.message}" if $DEBUG
              next
            end
          end
        end

        # Load namespace declarations from C element to Ruby element
        # @param elem_ptr [FFI::Pointer] the C element pointer
        # @param elem [Element] the Ruby element
        # @return [void]
        def load_namespaces(elem_ptr, elem)
          count = Taurus::FFI.taurus_element_namespace_count(elem_ptr)

          count.times do |i|
            ns_ptr = Taurus::FFI.taurus_element_namespace_decl(elem_ptr, i)
            next if ns_ptr.null?

            prefix = Taurus::FFI.taurus_namespace_prefix(ns_ptr)
            uri = Taurus::FFI.taurus_namespace_uri(ns_ptr)

            if uri && !uri.empty?
              prefix = nil if prefix && prefix.empty?
              elem.add_namespace(prefix, uri)
            end
          end
        end

        # Load children from C element to Ruby element
        # @param elem_ptr [FFI::Pointer] the C element pointer
        # @param elem [Element] the Ruby element
        # @param doc_ptr [FFI::Pointer] the document pointer (optional)
        # @return [void]
        def load_children(elem_ptr, elem, doc_ptr = nil)
          count = Taurus::FFI.taurus_element_child_count(elem_ptr)

          # If we have text content, add it as a text node
          if elem.instance_variable_get(:@_text_content)
            elem << elem.instance_variable_get(:@_text_content)
          end

          count.times do |i|
            child_ptr = Taurus::FFI.taurus_element_child(elem_ptr, i)
            next if child_ptr.null?

            # Recursively convert child element
            child = element_from_ptr(child_ptr, doc_ptr)
            elem << child if child
          end
        end

        # Convert XPath result to Ruby value
        # @param result_ptr [FFI::Pointer] the XPath result pointer
        # @param doc_ptr [FFI::Pointer] the document pointer (for full element hydration)
        # @return [Array<Element>, String, Float, Boolean] the converted result
        def xpath_result_to_ruby(result_ptr, doc_ptr = nil)
          return nil if result_ptr.null?

          # Get result type
          type_int = Taurus::FFI.taurus_xpath_result_get_type(result_ptr)
          type = Taurus::FFI.xpath_result_type_to_sym(type_int)

          case type
          when :boolean
            bool_int = Taurus::FFI.taurus_xpath_result_as_boolean(result_ptr)
            bool_int != 0

          when :number
            Taurus::FFI.taurus_xpath_result_as_number(result_ptr)

          when :string
            str = Taurus::FFI.taurus_xpath_result_as_string(result_ptr)
            # v1.1.0: FFI returns ASCII-8BIT by default, force UTF-8 encoding
            # The C library produces correct UTF-8 bytes, we just need to mark them correctly
            str.force_encoding(Encoding::UTF_8) if str
            str

          when :nodeset
            # Convert nodeset to Ruby array by reading XPathNodeSet struct directly
            # This bypasses the public API which filters out attributes

            # struct taurus_xpath_result { type(4+4pad), value(union at offset 8) }
            # value.nodeset_value is XPathNodeSet*
            nodeset_ptr = result_ptr.get_pointer(8)
            return [] if nodeset_ptr.null?

            # struct xpath_nodeset { void** nodes, size_t count, size_t capacity }
            nodes_array_ptr = nodeset_ptr.read_pointer  # void** nodes at offset 0
            count = nodeset_ptr.get_uint64(8)           # size_t count at offset 8 (8 bytes on 64-bit)

            result = []
            count.times do |i|
              # Read void* from nodes array
              node_ptr = nodes_array_ptr.get_pointer(i * ::FFI::Pointer.size)
              next if node_ptr.null?

              # Type detection: Only attribute nodes have a node_type field!
              # Elements have char* name as first field (8 bytes on 64-bit).
              # Read first 4 bytes and check if it's the ATTRIBUTE enum value (1).
              # If not 1, treat as element (no type field exists).
              first_int = node_ptr.read_int
              puts "DEBUG: Node #{i}: first_int = #{first_int}, hex = 0x#{first_int.to_s(16)}" if ENV['XPATH_DEBUG']

              # Type detection strategy:
              # - Attribute nodes have node_type (int, value 1) as first 4 bytes
              # - Element nodes have name pointer (8 bytes) as first field
              #
              # We check the first 4 bytes. If it's exactly 1, it's an attribute.
              # Otherwise, try to convert as element, and if that fails, try as attribute.

              if first_int == 1
                # Attribute node (node_type == TAURUS_NODE_ATTRIBUTE)
                # struct TaurusAttributeNode: node_type(4+4pad), name(8), value(8), ns_uri(8), owner(8)
                begin
                  value_ptr = node_ptr.get_pointer(16)  # offset 16 = value field
                  attr_value = value_ptr.null? ? "" : value_ptr.read_string
                  result << attr_value
                rescue => e
                  warn "Warning: Failed to read attribute at index #{i}: #{e.message}" if $DEBUG
                  next
                end
              else
                # Element node - call element_from_ptr to fully hydrate with children/attributes
                begin
                  # Use element_from_ptr to properly populate element with all structure
                  elem = element_from_ptr(node_ptr, doc_ptr)
                  if elem
                    result << elem
                  else
                    warn "Warning: Element at index #{i} could not be converted" if $DEBUG
                  end
                rescue => e
                  warn "Warning: Failed to convert element at index #{i}: #{e.message}" if $DEBUG
                  next
                end
              end
            end

            result

          else
            nil
          end
        end
      end
    end
  end
end