# frozen_string_literal: true

module Taurus
  module FFI
    # ========================================================================
    # Error Handling
    # ========================================================================
    
    module ErrorHandling
      # Map error codes to symbols
      ERROR_CODE_SYMBOLS = {
        ErrorCode::NULL_INPUT => :null_input,
        ErrorCode::EMPTY_INPUT => :empty_input,
        ErrorCode::PARSE_FAILED => :parse_failed,
        ErrorCode::INVALID_XML => :invalid_xml,
        ErrorCode::UNCLOSED_TAG => :unclosed_tag,
        ErrorCode::INVALID_ATTR => :invalid_attr,
        ErrorCode::ENCODING => :encoding,
        ErrorCode::NAMESPACE => :namespace,
        ErrorCode::MALFORMED => :malformed,
        ErrorCode::XPATH_SYNTAX => :xpath_syntax,
        ErrorCode::XPATH_FUNCTION => :xpath_function,
        ErrorCode::XPATH_TYPE_MISMATCH => :xpath_type_mismatch,
        ErrorCode::XPATH_NAMESPACE => :xpath_namespace,
        ErrorCode::XPATH_UNKNOWN_AXIS => :xpath_unknown_axis,
        ErrorCode::EVAL_CONTEXT => :eval_context,
        ErrorCode::EVAL_ARGUMENT => :eval_argument,
        ErrorCode::EVAL_OVERFLOW => :eval_overflow,
        ErrorCode::OUT_OF_MEMORY => :out_of_memory,
        ErrorCode::INTERNAL => :internal
      }.freeze
      
      # Check for errors after FFI call and raise appropriate Ruby exception
      # @raise [ParseError] if a parse error occurred
      # @raise [XPathError] if an XPath error occurred
      # @raise [Error] for other errors
      def self.check_error!
        error_msg = Taurus::FFI.taurus_last_error
        return if error_msg.nil? || error_msg.empty?
        
        error_code = Taurus::FFI.taurus_last_error_code
        line = Taurus::FFI.taurus_parse_error_line || 0
        column = Taurus::FFI.taurus_parse_error_column || 0
        context = Taurus::FFI.taurus_error_context
        byte_offset = Taurus::FFI.taurus_error_byte_offset || 0
        
        # Convert to symbol
        code_symbol = ERROR_CODE_SYMBOLS[error_code] || :unknown
        
        Taurus::FFI.taurus_clear_error
        
        # Determine exception type based on error code
        exception_class = case error_code
        when ErrorCode::NULL_INPUT, ErrorCode::EMPTY_INPUT,
             ErrorCode::UNCLOSED_TAG, ErrorCode::INVALID_ATTR,
             ErrorCode::ENCODING, ErrorCode::NAMESPACE,
             ErrorCode::MALFORMED, ErrorCode::PARSE_FAILED,
             ErrorCode::INVALID_XML
          Taurus::ParseError
        when ErrorCode::XPATH_SYNTAX, ErrorCode::XPATH_FUNCTION,
             ErrorCode::XPATH_TYPE_MISMATCH, ErrorCode::XPATH_NAMESPACE,
             ErrorCode::XPATH_UNKNOWN_AXIS
          Taurus::XPathError
        when ErrorCode::EVAL_CONTEXT, ErrorCode::EVAL_ARGUMENT,
             ErrorCode::EVAL_OVERFLOW
          Taurus::EvaluationError
        else
          Taurus::Error
        end
        
        # Create exception with all attributes
        exception = exception_class.new(
          error_msg,
          code: code_symbol,
          line: line,
          column: column,
          byte_offset: byte_offset,
          context: context
        )
        
        raise exception
      end
      
      # Wrap FFI call with error checking
      # @yield block to execute
      # @return result of block
      # @raise [ParseError, Error] if error occurred
      def self.with_error_check
        result = yield
        check_error! if result.nil? || (result.respond_to?(:null?) && result.null?)
        result
      end
    end
    
    # ========================================================================
    # Convenience Methods
    # ========================================================================
    
    # Check for errors and raise if any
    def self.check_error!
      ErrorHandling.check_error!
    end
    
    # Wrap call with error checking
    def self.with_error_check(&block)
      ErrorHandling.with_error_check(&block)
    end
  end
end