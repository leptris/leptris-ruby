# frozen_string_literal: true

require 'ffi'

module Taurus
  module FFI
    # ========================================================================
    # Memory Management with AutoPointer
    # ========================================================================
    
    # AutoPointer for taurus_document - automatically frees when GC'd
    class DocumentPointer < ::FFI::AutoPointer
      def self.release(ptr)
        Taurus::FFI.taurus_document_free(ptr) unless ptr.null?
      end
    end
    
    # AutoPointer for taurus_xpath_result - automatically frees when GC'd
    class XPathResultPointer < ::FFI::AutoPointer
      def self.release(ptr)
        Taurus::FFI.taurus_xpath_result_free(ptr) unless ptr.null?
      end
    end
    
    # ========================================================================
    # Memory Management Helpers
    # ========================================================================
    
    module MemoryHelpers
      # Wrap a document pointer with AutoPointer for automatic cleanup
      # @param ptr [FFI::Pointer] the document pointer from C
      # @return [DocumentPointer] wrapped pointer that auto-frees
      def self.wrap_document(ptr)
        return nil if ptr.null?
        DocumentPointer.new(ptr)
      end
      
      # Wrap an XPath result pointer with AutoPointer for automatic cleanup
      # @param ptr [FFI::Pointer] the result pointer from C
      # @return [XPathResultPointer] wrapped pointer that auto-frees
      def self.wrap_xpath_result(ptr)
        return nil if ptr.null?
        XPathResultPointer.new(ptr)
      end
      
      # Free a string allocated by C
      # @param str_ptr [FFI::Pointer] pointer to C-allocated string
      # @return [String, nil] the string content before freeing
      def self.free_c_string(str_ptr)
        return nil if str_ptr.null?
        str = str_ptr.read_string
        # Note: According to taurus_xpath_result_as_string docs,
        # caller must free with free(). FFI handles this via MemoryPointer.
        ::FFI::MemoryPointer.from_string(str).free
        str
      end
    end
  end
end