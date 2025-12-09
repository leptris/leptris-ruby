# frozen_string_literal: true

# Load Ruby classes first
require_relative "taurus/version"
require_relative "taurus/node"
require_relative "taurus/element"
require_relative "taurus/document"
require_relative "taurus/node_set"
require_relative "taurus/xpath"

# Load FFI modules
require_relative "taurus/ffi/library"
require_relative "taurus/ffi/types"
require_relative "taurus/ffi/memory"
require_relative "taurus/ffi/errors"
require_relative "taurus/ffi/bridge"

# Taurus is a high-performance XML parser for Ruby with complete XML Namespaces 1.0
# and XPath 1.0 support. It provides Ox-level parsing speed with full features
# implemented in C for maximum performance.
#
# @example Basic parsing
#   doc = Taurus.parse('<root><item id="1">content</item></root>')
#   root = doc.root
#   root.name # => "root"
#   root.nodes.first[:id] # => "1"
#
# @example Parsing from file
#   doc = Taurus.parse_file('document.xml')
#
# @example XPath queries
#   doc = Taurus.parse('<library><book><title>Ruby</title></book></library>')
#   titles = doc.xpath('//title')
#   count = doc.xpath('count(//book)') # => 1.0
#
# @example Working with namespaces
#   xml = '<root xmlns="http://example.org"><item/></root>'
#   doc = Taurus.parse(xml)
#   doc.root.namespace[:href] # => "http://example.org"
#
# @see Document
# @see Element
# @see XPath
module Taurus
  # Base error class for Taurus library
  class Error < StandardError; end

  # Raised when XML parsing fails due to malformed input
  #
  # @example
  #   Taurus.parse('<unclosed>') # raises Taurus::ParseError
  class ParseError < Error
    # @return [Symbol] error code symbol
    attr_reader :code
    
    # @return [Integer] line number where error occurred (1-based, 0 if not available)
    attr_reader :line
    
    # @return [Integer] column number where error occurred (1-based, 0 if not available)
    attr_reader :column
    
    # @return [Integer] byte offset where error occurred (0 if not available)
    attr_reader :byte_offset
    
    # @return [String, nil] context snippet showing code around error
    attr_reader :context
    
    def initialize(message, code: :parse_failed, line: 0, column: 0, byte_offset: 0, context: nil)
      super(message)
      @code = code
      @line = line
      @column = column
      @byte_offset = byte_offset
      @context = context
    end
  end

  # Raised when XPath evaluation fails due to syntax or semantic errors
  #
  # @example
  #   doc.xpath('//book:title') # raises Taurus::XPathError if 'book' prefix not registered
  class XPathError < Error
    attr_reader :code, :line, :column, :byte_offset, :context
    
    def initialize(message, code: :xpath_error, line: 0, column: 0, byte_offset: 0, context: nil)
      super(message)
      @code = code
      @line = line
      @column = column
      @byte_offset = byte_offset
      @context = context
    end
  end

  # Raised when XPath evaluation fails due to runtime issues
  #
  # @example
  #   doc.xpath('sum("not a number")') # raises Taurus::EvaluationError
  class EvaluationError < Error
    attr_reader :code, :line, :column, :byte_offset, :context
    
    def initialize(message, code: :eval_error, line: 0, column: 0, byte_offset: 0, context: nil)
      super(message)
      @code = code
      @line = line
      @column = column
      @byte_offset = byte_offset
      @context = context
    end
  end

  class << self
    # Parse an XML string and return a Document
    #
    # Parses the given XML string using the native libtaurus C library via FFI.
    # Returns a fully constructed Ruby Document object with all elements,
    # attributes, and namespace information.
    #
    # @param xml_string [String] the XML string to parse
    # @return [Document] the parsed document
    # @raise [ParseError] if XML is malformed
    #
    # @example
    #   doc = Taurus.parse('<root><item id="1">content</item></root>')
    #   doc.root.name # => "root"
    #   doc.root.nodes.first[:id] # => "1"
    #
    # @see .parse_file
    def parse(xml_string)
      # Validate input in Ruby layer first
      if xml_string.nil?
        raise ParseError.new(
          "NULL input provided",
          code: :null_input,
          line: 0,
          column: 0
        )
      end
      
      if xml_string.empty?
        raise ParseError.new(
          "Empty input provided",
          code: :empty_input,
          line: 0,
          column: 0
        )
      end
      
      FFI::ErrorHandling.with_error_check do
        # Call C library to parse XML
        doc_ptr = FFI.taurus_parse(xml_string, xml_string.bytesize)
        
        if doc_ptr.null?
          FFI::ErrorHandling.check_error!
          raise ParseError, "Failed to parse XML"
        end
        
        # Wrap pointer for automatic cleanup
        doc_ptr = FFI::MemoryHelpers.wrap_document(doc_ptr)
        
        # Convert C document to Ruby object
        FFI::Bridge.document_from_ptr(doc_ptr)
      end
    end
    
    # Parse an XML file and return a Document
    #
    # This is a convenience method that reads the file and calls {.parse}.
    #
    # @param file_path [String] path to the XML file
    # @return [Document] the parsed document
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [ParseError] if XML is malformed
    #
    # @example
    #   doc = Taurus.parse_file('books.xml')
    #   doc.root.name # => root element name
    #
    # @see .parse
    def parse_file(file_path)
      xml_string = File.read(file_path)
      parse(xml_string)
    end
    
    # Evaluate an XPath expression on a document
    #
    # This is called internally by Document#xpath and Element#xpath.
    # Uses the native C XPath evaluator via FFI.
    #
    # @param doc [Document] the document context
    # @param expression [String] the XPath expression
    # @param context_node [Element, Document] the context node for evaluation
    # @param namespaces [Hash, nil] custom namespace mappings (reserved for future use)
    # @return [Array<Element>, String, Float, Boolean] the XPath result
    #
    # @api private
    def xpath_evaluate(doc, expression, context_node = nil, namespaces = nil)
      # Note: namespaces parameter reserved for v0.9.0 custom namespace registration
      # Currently, namespaces are auto-detected from the document (v0.8.0)
      FFI::ErrorHandling.with_error_check do
        # Extract C pointer from Ruby Document object or from context node
        doc_ptr = doc.instance_variable_get(:@_c_ptr)
        
        # If doc doesn't have pointer, try to get it from context_node
        # (happens when Element#xpath creates a temporary Document)
        if !doc_ptr && context_node
          doc_ptr = context_node.instance_variable_get(:@_c_doc_ptr)
        end
        
        unless doc_ptr
          raise Error, "Document has no C pointer (not created via Taurus.parse)"
        end
        
        # Call C library to evaluate XPath
        result_ptr = if context_node && context_node != doc
          # Extract C pointer from context node
          context_ptr = context_node.instance_variable_get(:@_c_ptr)
          unless context_ptr
            raise Error, "Context node has no C pointer"
          end
          
          # Use context node variant
          FFI.taurus_xpath_eval_with_context(
            doc_ptr,
            context_ptr,
            expression,
            expression.bytesize
          )
        else
          # Use document variant
          FFI.taurus_xpath_eval(doc_ptr, expression, expression.bytesize)
        end
        
        if result_ptr.null?
          FFI::ErrorHandling.check_error!
          raise Error, "XPath evaluation failed"
        end
        
        # Wrap pointer for automatic cleanup
        result_ptr = FFI::MemoryHelpers.wrap_xpath_result(result_ptr)
        
        # Convert C result to Ruby value, passing doc_ptr for full element hydration
        FFI::Bridge.xpath_result_to_ruby(result_ptr, doc_ptr)
      end
    end
  end
end

# Load adapter after Taurus module is fully defined
require_relative "taurus/adapter"