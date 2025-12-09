# frozen_string_literal: true

require 'ffi'

module Taurus
  module FFI
    # ========================================================================
    # XPath Result Types
    # ========================================================================
    
    # XPath result type enumeration
    module XPathResultType
      BOOLEAN = 0  # Boolean result (true/false)
      NUMBER = 1   # Number result (double)
      STRING = 2   # String result
      NODESET = 3  # Node-set result (array of elements)
    end
    
    # ========================================================================
    # Error Codes
    # ========================================================================
    
    # Error codes - matches taurus_error_code in types.h
    module ErrorCode
      # Success
      OK = 0
      
      # Parse errors (1xx) - XML parsing issues
      NULL_INPUT = 1
      EMPTY_INPUT = 2
      PARSE_FAILED = 3
      INVALID_XML = 4
      UNCLOSED_TAG = 100
      INVALID_ATTR = 101
      ENCODING = 102
      NAMESPACE = 103
      MALFORMED = 104
      
      # XPath errors (2xx) - Query syntax and semantics
      XPATH_SYNTAX = 200
      XPATH_FUNCTION = 201
      XPATH_TYPE_MISMATCH = 202
      XPATH_NAMESPACE = 203
      XPATH_UNKNOWN_AXIS = 204
      
      # Evaluation errors (3xx) - Runtime issues
      EVAL_CONTEXT = 300
      EVAL_ARGUMENT = 301
      EVAL_OVERFLOW = 302
      
      # Generic errors (9xx)
      OUT_OF_MEMORY = 900
      INTERNAL = 999
    end
    
    # ========================================================================
    # Parse Options Structure
    # ========================================================================
    
    # XML parse options
    class ParseOptions < ::FFI::Struct
      layout :strict, :int,               # Strict XML validation (1=strict, 0=lenient)
             :preserve_whitespace, :int,  # Preserve whitespace-only text nodes
             :track_positions, :int       # Track line/column positions for errors
      
      # Initialize with default values
      def self.default
        opts = new
        opts[:strict] = 1
        opts[:preserve_whitespace] = 0
        opts[:track_positions] = 0
        opts
      end
    end
    
    # ========================================================================
    # Helper Methods
    # ========================================================================
    
    # Convert XPath result type integer to symbol
    # @param type_int [Integer] the result type as integer
    # @return [Symbol] :boolean, :number, :string, or :nodeset
    def self.xpath_result_type_to_sym(type_int)
      case type_int
      when XPathResultType::BOOLEAN then :boolean
      when XPathResultType::NUMBER then :number
      when XPathResultType::STRING then :string
      when XPathResultType::NODESET then :nodeset
      else :unknown
      end
    end
    
    # Convert error code integer to symbol
    # @param code_int [Integer] the error code as integer
    # @return [Symbol] error code symbol
    def self.error_code_to_sym(code_int)
      case code_int
      when ErrorCode::OK then :ok
      # Parse errors
      when ErrorCode::NULL_INPUT then :null_input
      when ErrorCode::EMPTY_INPUT then :empty_input
      when ErrorCode::PARSE_FAILED then :parse_failed
      when ErrorCode::INVALID_XML then :invalid_xml
      when ErrorCode::UNCLOSED_TAG then :unclosed_tag
      when ErrorCode::INVALID_ATTR then :invalid_attr
      when ErrorCode::ENCODING then :encoding
      when ErrorCode::NAMESPACE then :namespace
      when ErrorCode::MALFORMED then :malformed
      # XPath errors
      when ErrorCode::XPATH_SYNTAX then :xpath_syntax
      when ErrorCode::XPATH_FUNCTION then :xpath_function
      when ErrorCode::XPATH_TYPE_MISMATCH then :xpath_type_mismatch
      when ErrorCode::XPATH_NAMESPACE then :xpath_namespace
      when ErrorCode::XPATH_UNKNOWN_AXIS then :xpath_unknown_axis
      # Evaluation errors
      when ErrorCode::EVAL_CONTEXT then :eval_context
      when ErrorCode::EVAL_ARGUMENT then :eval_argument
      when ErrorCode::EVAL_OVERFLOW then :eval_overflow
      # Generic errors
      when ErrorCode::OUT_OF_MEMORY then :out_of_memory
      when ErrorCode::INTERNAL then :internal
      else :unknown
      end
    end
  end
end