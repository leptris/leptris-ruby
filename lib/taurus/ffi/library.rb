# frozen_string_literal: true

require 'ffi'

module Taurus
  module FFI
    extend ::FFI::Library
    
    # Dynamic library loading
    # Try to find libtaurus in common locations
    lib_paths = [
      File.expand_path('../../../build/lib/libtaurus.dylib', __dir__),  # Build directory (macOS)
      File.expand_path('../../../build/lib/libtaurus.so', __dir__),     # Build directory (Linux)
      File.expand_path('../../../lib/libtaurus.dylib', __dir__),        # Installed location (macOS)
      File.expand_path('../../../lib/libtaurus.so', __dir__),           # Installed location (Linux)
      'taurus',  # System library path
    ]
    
    lib_path = lib_paths.find { |path| File.exist?(path) } || 'taurus'
    ffi_lib lib_path
    
    # ========================================================================
    # Opaque Types
    # ========================================================================
    
    typedef :pointer, :taurus_document
    typedef :pointer, :taurus_element
    typedef :pointer, :taurus_attribute
    typedef :pointer, :taurus_namespace
    typedef :pointer, :taurus_xpath_result
    
    # ========================================================================
    # Version Functions
    # ========================================================================
    
    attach_function :taurus_version, [], :string
    attach_function :taurus_version_components, [:pointer, :pointer, :pointer], :void
    
    # ========================================================================
    # Parse Options
    # ========================================================================
    
    attach_function :taurus_parse_options_init, [:pointer], :void
    
    # ========================================================================
    # Document Functions
    # ========================================================================
    
    attach_function :taurus_parse, [:string, :size_t], :taurus_document
    attach_function :taurus_parse_with_options, [:string, :size_t, :pointer], :taurus_document
    attach_function :taurus_document_free, [:taurus_document], :void
    attach_function :taurus_document_root, [:taurus_document], :taurus_element
    attach_function :taurus_document_encoding, [:taurus_document], :string
    
    # ========================================================================
    # Element Functions
    # ========================================================================
    
    attach_function :taurus_element_name, [:taurus_element], :string
    attach_function :taurus_element_namespace, [:taurus_element], :string
    attach_function :taurus_element_prefix, [:taurus_element], :string
    attach_function :taurus_element_text, [:taurus_element], :string
    attach_function :taurus_element_parent, [:taurus_element], :taurus_element
    attach_function :taurus_element_child_count, [:taurus_element], :size_t
    attach_function :taurus_element_child, [:taurus_element, :size_t], :taurus_element
    
    # ========================================================================
    # Attribute Functions
    # ========================================================================
    
    attach_function :taurus_element_attribute_count, [:taurus_element], :size_t
    attach_function :taurus_element_attribute, [:taurus_element, :size_t], :taurus_attribute
    attach_function :taurus_element_get_attribute, [:taurus_element, :string], :string
    attach_function :taurus_element_has_attribute, [:taurus_element, :string], :int
    attach_function :taurus_attribute_name, [:taurus_attribute], :string
    attach_function :taurus_attribute_value, [:taurus_attribute], :string
    attach_function :taurus_attribute_namespace, [:taurus_attribute], :string
    
    # ========================================================================
    # Namespace Functions
    # ========================================================================
    
    attach_function :taurus_element_namespace_count, [:taurus_element], :size_t
    attach_function :taurus_element_namespace_decl, [:taurus_element, :size_t], :taurus_namespace
    attach_function :taurus_element_resolve_namespace, [:taurus_element, :string], :string
    attach_function :taurus_namespace_prefix, [:taurus_namespace], :string
    attach_function :taurus_namespace_uri, [:taurus_namespace], :string
    
    # ========================================================================
    # XPath Functions
    # ========================================================================
    
    attach_function :taurus_xpath_eval, [:taurus_document, :string, :size_t], :taurus_xpath_result
    attach_function :taurus_xpath_eval_with_context, 
                    [:taurus_document, :taurus_element, :string, :size_t], 
                    :taurus_xpath_result
    attach_function :taurus_xpath_result_free, [:taurus_xpath_result], :void
    attach_function :taurus_xpath_result_get_type, [:taurus_xpath_result], :int
    attach_function :taurus_xpath_result_as_boolean, [:taurus_xpath_result], :int
    attach_function :taurus_xpath_result_as_number, [:taurus_xpath_result], :double
    attach_function :taurus_xpath_result_as_string, [:taurus_xpath_result], :string
    attach_function :taurus_xpath_result_nodeset_size, [:taurus_xpath_result], :size_t
    attach_function :taurus_xpath_result_nodeset_get, [:taurus_xpath_result, :size_t], :taurus_element
    attach_function :taurus_xpath_function_supported, [:string], :int
    attach_function :taurus_xpath_supported_functions, [], :pointer
    
    # ========================================================================
    # Error Functions
    # ========================================================================
    
    attach_function :taurus_last_error, [], :string
    attach_function :taurus_last_error_code, [], :int
    attach_function :taurus_error_string, [:int], :string
    attach_function :taurus_clear_error, [], :void
    attach_function :taurus_parse_error_line, [], :int
    attach_function :taurus_parse_error_column, [], :int
    attach_function :taurus_error_context, [], :string
    attach_function :taurus_error_byte_offset, [], :size_t
  end
end