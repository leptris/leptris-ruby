# frozen_string_literal: true

require "ffi"

module Leptris
  module XML
    module FFI
      extend ::FFI::Library

      ffi_lib [
        ENV["LEPTRIS_LIB_PATH"],
        File.expand_path("../../libleptris.dylib", __dir__),
        File.expand_path("../../libleptris.so", __dir__),
        "/usr/local/lib/libleptris.dylib",
        "/usr/local/lib/libleptris.so",
        "leptris",
      ].compact

      typedef :pointer, :leptris_document
      typedef :pointer, :leptris_element
      typedef :pointer, :leptris_node_ref
      typedef :pointer, :leptris_attribute
      typedef :pointer, :leptris_doctype
      typedef :pointer, :leptris_xpath_result
      typedef :pointer, :leptris_xpath_var_set
      typedef :pointer, :leptris_sax_parser
      typedef :int, :leptris_status

      class SAXHandler < ::FFI::Struct
        layout \
          :start_document, :pointer,
          :end_document, :pointer,
          :start_element, :pointer,
          :end_element, :pointer,
          :characters, :pointer,
          :comment, :pointer,
          :cdata, :pointer,
          :processing_instruction, :pointer,
          :start_prefix_mapping, :pointer,
          :end_prefix_mapping, :pointer,
          :error, :pointer
      end

      class SerializeOptions < ::FFI::Struct
        layout \
          :indent, :int,
          :xml_declaration, :int,
          :encoding, :pointer
      end

      attach_function :leptris_version, [], :string
      attach_function :leptris_version_components, [:pointer, :pointer, :pointer], :void

      attach_function :leptris_parse_string,
        [:string, :size_t, :pointer], :leptris_document
      attach_function :leptris_parse_string_flags,
        [:string, :size_t, :uint, :pointer], :leptris_document
      attach_function :leptris_parse_string_inplace,
        [:pointer, :size_t, :pointer], :leptris_document
      attach_function :leptris_parse_string_with_encoding,
        [:string, :size_t, :pointer], :leptris_document
      attach_function :leptris_parse_file,
        [:string, :pointer], :leptris_document
      attach_function :leptris_load_file,
        [:string, :pointer], :pointer
      attach_function :leptris_document_free,
        [:leptris_document], :void
      attach_function :leptris_document_root,
        [:leptris_document], :leptris_element
      attach_function :leptris_document_encoding,
        [:leptris_document], :string
      attach_function :leptris_document_finalize_strings,
        [:leptris_document], :int
      attach_function :leptris_document_adopt_child,
        [:leptris_document, :leptris_document], :void
      attach_function :leptris_document_set_strict,
        [:leptris_document, :int], :leptris_status
      attach_function :leptris_document_get_strict,
        [:leptris_document], :int
      attach_function :leptris_document_freeze,
        [:leptris_document], :leptris_status
      attach_function :leptris_document_is_frozen,
        [:leptris_document], :int
      attach_function :leptris_set_strict_mode, [:int], :void
      attach_function :leptris_get_strict_mode, [], :int
      attach_function :leptris_set_max_depth, [:int], :void
      attach_function :leptris_get_max_depth, [], :int
      attach_function :leptris_xinclude_process,
        [:leptris_document, :string], :leptris_status
      attach_function :leptris_xinclude_is_include_element,
        [:leptris_element], :int
      attach_function :leptris_xinclude_is_fallback_element,
        [:leptris_element], :int
      attach_function :leptris_xinclude_get_href, [:leptris_element], :string
      attach_function :leptris_xinclude_get_parse, [:leptris_element], :string
      attach_function :leptris_xinclude_get_xpointer, [:leptris_element], :string
      # leptris_xinclude_get_encoding is declared in leptris.h but not exported
      # from the v0.4.4 dylib (likely same visibility bug as the serialize
      # functions; see upstream issue #166). Re-add once #173 / v0.4.5 ships.

      attach_function :leptris_node_get_type,
        [:leptris_node_ref], :int
      attach_function :leptris_node_first_child,
        [:leptris_node_ref], :leptris_node_ref
      attach_function :leptris_node_last_child,
        [:leptris_node_ref], :leptris_node_ref
      attach_function :leptris_node_next_sibling,
        [:leptris_node_ref], :leptris_node_ref
      attach_function :leptris_node_previous_sibling,
        [:leptris_node_ref], :leptris_node_ref
      attach_function :leptris_node_child_count,
        [:leptris_node_ref], :size_t
      attach_function :leptris_node_as_element,
        [:leptris_node_ref], :leptris_element
      attach_function :leptris_element_as_node,
        [:leptris_element], :leptris_node_ref
      attach_function :leptris_node_get_binding_wrapper,
        [:leptris_node_ref], :pointer
      attach_function :leptris_node_set_binding_wrapper,
        [:leptris_node_ref, :pointer], :void
      attach_function :leptris_node_parent,
        [:leptris_node_ref], :leptris_element
      attach_function :leptris_node_unlink,
        [:leptris_node_ref], :leptris_status
      attach_function :leptris_node_line,
        [:leptris_node_ref], :int
      attach_function :leptris_node_compare,
        [:leptris_node_ref, :leptris_node_ref], :int
      attach_function :leptris_node_traverse,
        [:leptris_node_ref, :int, :pointer, :pointer], :int

      attach_function :leptris_text_node_get_content,
        [:leptris_node_ref], :string
      attach_function :leptris_comment_node_get_content,
        [:leptris_node_ref], :string
      attach_function :leptris_cdata_node_get_content,
        [:leptris_node_ref], :string
      attach_function :leptris_pi_node_get_target,
        [:leptris_node_ref], :string
      attach_function :leptris_pi_node_get_data,
        [:leptris_node_ref], :string
      attach_function :leptris_text_node_create,
        [:leptris_document, :string], :leptris_node_ref
      attach_function :leptris_comment_node_create,
        [:leptris_document, :string], :leptris_node_ref
      attach_function :leptris_cdata_node_create,
        [:leptris_document, :string], :leptris_node_ref
      attach_function :leptris_pi_node_create,
        [:leptris_document, :string, :string], :leptris_node_ref
      attach_function :leptris_text_node_set_content,
        [:leptris_node_ref, :string], :leptris_status
      attach_function :leptris_comment_node_set_content,
        [:leptris_node_ref, :string], :leptris_status
      attach_function :leptris_cdata_node_set_content,
        [:leptris_node_ref, :string], :leptris_status
      attach_function :leptris_pi_node_set_target,
        [:leptris_node_ref, :string], :leptris_status
      attach_function :leptris_pi_node_set_data,
        [:leptris_node_ref, :string], :leptris_status

      attach_function :leptris_element_name,
        [:leptris_element], :string
      attach_function :leptris_element_text,
        [:leptris_element], :string
      attach_function :leptris_element_text_int,
        [:leptris_element, :int], :int
      attach_function :leptris_element_text_uint,
        [:leptris_element, :uint], :uint
      attach_function :leptris_element_text_double,
        [:leptris_element, :double], :double
      attach_function :leptris_element_text_float,
        [:leptris_element, :float], :float
      attach_function :leptris_element_text_bool,
        [:leptris_element, :int], :int
      attach_function :leptris_element_attribute,
        [:leptris_element, :string], :string
      attach_function :leptris_element_attribute_string,
        [:leptris_element, :string, :string], :string
      attach_function :leptris_element_attribute_int,
        [:leptris_element, :string, :int], :int
      attach_function :leptris_element_attribute_uint,
        [:leptris_element, :string, :uint], :uint
      attach_function :leptris_element_attribute_double,
        [:leptris_element, :string, :double], :double
      attach_function :leptris_element_attribute_float,
        [:leptris_element, :string, :float], :float
      attach_function :leptris_element_attribute_bool,
        [:leptris_element, :string, :int], :int
      # leptris_element_has_attribute is declared in leptris.h but not exported
      # from the v0.4.4 dylib (likely visibility bug; see upstream #166).
      # Ruby-level Element#key? will emulate via attribute lookup.
      attach_function :leptris_element_attribute_count,
        [:leptris_element], :size_t
      attach_function :leptris_element_attribute_name_at,
        [:leptris_element, :size_t], :string
      attach_function :leptris_element_attribute_value_at,
        [:leptris_element, :size_t], :string
      attach_function :leptris_element_remove_all_attributes,
        [:leptris_element], :leptris_status

      attach_function :leptris_element_child_count,
        [:leptris_element], :size_t
      attach_function :leptris_element_child,
        [:leptris_element, :size_t], :leptris_element
      attach_function :leptris_element_parent,
        [:leptris_element], :leptris_element
      attach_function :leptris_element_root,
        [:leptris_element], :leptris_element
      attach_function :leptris_element_child_value,
        [:leptris_element], :string
      attach_function :leptris_element_hash_value,
        [:leptris_element], :size_t
      attach_function :leptris_element_find_child,
        [:leptris_element, :string], :leptris_element
      attach_function :leptris_element_find_child_by_attr,
        [:leptris_element, :string, :string, :string], :leptris_element
      attach_function :leptris_element_next_sibling,
        [:leptris_element, :string], :leptris_element
      attach_function :leptris_element_previous_sibling,
        [:leptris_element, :string], :leptris_element
      attach_function :leptris_element_first_child,
        [:leptris_element, :string], :leptris_element
      attach_function :leptris_element_last_child,
        [:leptris_element, :string], :leptris_element
      attach_function :leptris_element_first_child_any,
        [:leptris_element], :leptris_element
      attach_function :leptris_element_last_child_any,
        [:leptris_element], :leptris_element
      attach_function :leptris_element_next_sibling_any,
        [:leptris_element], :leptris_element
      attach_function :leptris_element_previous_sibling_any,
        [:leptris_element], :leptris_element

      attach_function :leptris_element_create,
        [:leptris_document, :string], :leptris_element
      attach_function :leptris_element_set_name,
        [:leptris_element, :string], :leptris_status
      attach_function :leptris_element_set_text,
        [:leptris_element, :string], :leptris_status
      attach_function :leptris_element_set_attribute,
        [:leptris_element, :string, :string], :leptris_status
      attach_function :leptris_element_set_attribute_bool,
        [:leptris_element, :string, :int], :leptris_status
      attach_function :leptris_element_set_attribute_double,
        [:leptris_element, :string, :double], :leptris_status
      attach_function :leptris_element_set_attribute_float,
        [:leptris_element, :string, :float], :leptris_status
      attach_function :leptris_element_set_attribute_int,
        [:leptris_element, :string, :int], :leptris_status
      attach_function :leptris_element_set_attribute_uint,
        [:leptris_element, :string, :uint], :leptris_status
      attach_function :leptris_element_remove_attribute,
        [:leptris_element, :string], :leptris_status
      attach_function :leptris_element_append_child,
        [:leptris_element, :leptris_element], :leptris_status
      attach_function :leptris_element_prepend_child,
        [:leptris_element, :leptris_element], :leptris_status
      attach_function :leptris_element_insert_before,
        [:leptris_element, :leptris_element], :leptris_status
      attach_function :leptris_element_insert_after,
        [:leptris_element, :leptris_element], :leptris_status
      attach_function :leptris_element_remove_child,
        [:leptris_element, :leptris_element], :leptris_status
      attach_function :leptris_element_remove_children,
        [:leptris_element], :leptris_status
      attach_function :leptris_element_append_copy,
        [:leptris_element, :leptris_element], :leptris_element
      attach_function :leptris_element_prepend_copy,
        [:leptris_element, :leptris_element], :leptris_element
      attach_function :leptris_element_insert_copy_before,
        [:leptris_element, :leptris_element], :leptris_element
      attach_function :leptris_element_insert_copy_after,
        [:leptris_element, :leptris_element], :leptris_element

      attach_function :leptris_element_copy,
        [:leptris_element, :leptris_document], :leptris_element
      attach_function :leptris_document_copy,
        [:leptris_document], :leptris_document
      attach_function :leptris_node_get_xpath,
        [:leptris_node_ref], :pointer
      attach_function :leptris_parse_fragment,
        [:string, :size_t, :leptris_document, :pointer], :leptris_element

      attach_function :leptris_element_namespace,
        [:leptris_element], :string
      attach_function :leptris_element_namespace_for_prefix,
        [:leptris_element, :string], :string
      attach_function :leptris_element_namespace_count,
        [:leptris_element], :size_t
      attach_function :leptris_element_namespace_decl_prefix,
        [:leptris_element, :size_t], :string
      attach_function :leptris_element_namespace_decl_uri,
        [:leptris_element, :size_t], :string
      attach_function :leptris_element_add_namespace_definition,
        [:leptris_element, :string, :string], :leptris_status
      attach_function :leptris_element_set_default_namespace,
        [:leptris_element, :string], :leptris_status
      attach_function :leptris_element_remove_namespace_definition,
        [:leptris_element, :string], :leptris_status
      attach_function :leptris_namespace_uri, [:string], :string
      attach_function :leptris_namespace_prefix, [:string], :string

      attach_function :leptris_xpath_eval,
        [:leptris_document, :leptris_element, :string], :leptris_xpath_result
      attach_function :leptris_xpath_eval_with_vars,
        [:leptris_document, :string, :leptris_xpath_var_set], :leptris_xpath_result
      attach_function :leptris_xpath_eval_with_vars_context,
        [:leptris_document, :leptris_element, :string, :leptris_xpath_var_set],
        :leptris_xpath_result
      attach_function :leptris_xpath_result_type,
        [:leptris_xpath_result], :int
      attach_function :leptris_xpath_result_count,
        [:leptris_xpath_result], :size_t
      attach_function :leptris_xpath_result_get,
        [:leptris_xpath_result, :size_t], :leptris_element
      attach_function :leptris_xpath_result_get_nodes,
        [:leptris_xpath_result, :pointer, :size_t], :size_t
      attach_function :leptris_xpath_result_boolean,
        [:leptris_xpath_result], :int
      attach_function :leptris_xpath_result_number,
        [:leptris_xpath_result], :double
      attach_function :leptris_xpath_result_string,
        [:leptris_xpath_result], :pointer
      attach_function :leptris_xpath_result_free,
        [:leptris_xpath_result], :void
      attach_function :leptris_xpath_function_supported, [:string], :int
      attach_function :leptris_xpath_supported_functions, [], :pointer

      attach_function :leptris_xpath_variable_set_new,
        [], :leptris_xpath_var_set
      attach_function :leptris_xpath_variable_set_free,
        [:leptris_xpath_var_set], :void
      attach_function :leptris_xpath_variable_set_boolean,
        [:leptris_xpath_var_set, :string, :int], :leptris_status
      attach_function :leptris_xpath_variable_set_number,
        [:leptris_xpath_var_set, :string, :double], :leptris_status
      attach_function :leptris_xpath_variable_set_string,
        [:leptris_xpath_var_set, :string, :string], :leptris_status

      attach_function :leptris_sax_parse,
        [:string, :size_t, :pointer, :pointer], :int
      attach_function :leptris_sax_parser_create,
        [:pointer, :pointer], :leptris_sax_parser
      attach_function :leptris_sax_parser_feed,
        [:leptris_sax_parser, :string, :size_t, :int], :int
      attach_function :leptris_sax_parser_free,
        [:leptris_sax_parser], :void
      attach_function :leptris_sax_parser_set_streaming,
        [:leptris_sax_parser, :int], :int

      attach_function :leptris_document_serialize,
        [:leptris_document, :pointer], :pointer
      attach_function :leptris_element_serialize,
        [:leptris_element, :pointer], :pointer
      attach_function :leptris_document_save_file,
        [:leptris_document, :string, :pointer], :leptris_status
      attach_function :leptris_c14n_canonicalize,
        [:leptris_document, :int, :int], :pointer
      attach_function :leptris_c14n_canonicalize_subtree,
        [:leptris_element, :int, :int], :pointer
      attach_function :leptris_c14n_canonicalize_ex,
        [:leptris_document, :int, :int, :pointer, :int], :pointer
      attach_function :leptris_c14n_canonicalize_subtree_ex,
        [:leptris_element, :int, :int, :pointer, :int], :pointer

      attach_function :leptris_document_internal_subset,
        [:leptris_document], :leptris_doctype
      attach_function :leptris_doctype_get_name,
        [:leptris_doctype], :string
      attach_function :leptris_doctype_get_root_name,
        [:leptris_doctype], :string
      attach_function :leptris_doctype_get_public_id,
        [:leptris_doctype], :string
      attach_function :leptris_doctype_get_system_id,
        [:leptris_doctype], :string
      attach_function :leptris_doctype_get_internal_subset,
        [:leptris_doctype], :string

      attach_function :leptris_free_string, [:pointer], :void
      attach_function :leptris_explicit_cleanup, [], :void
      attach_function :leptris_set_memory_management_functions,
        [:pointer, :pointer], :void
      attach_function :leptris_get_memory_allocation_function, [], :pointer
      attach_function :leptris_get_memory_deallocation_function, [], :pointer
      attach_function :leptris_document_set_allocators,
        [:leptris_document, :pointer, :pointer], :leptris_status
      attach_function :leptris_status_string, [:leptris_status], :string

      LEPTRIS_OK = 0
      LEPTRIS_ERROR_MEMORY = -1
      LEPTRIS_ERROR_PARSE = -2
      LEPTRIS_ERROR_XPATH = -3
      LEPTRIS_ERROR_NULL_ARG = -4
      LEPTRIS_ERROR_INVALID_ARG = -5
      LEPTRIS_ERROR_NOT_FOUND = -6
      LEPTRIS_ERROR_IO = -7
      LEPTRIS_ERROR_NOT_IMPLEMENTED = -8

      XPATH_NODESET = 0
      XPATH_BOOLEAN = 1
      XPATH_NUMBER = 2
      XPATH_STRING = 3

      NODE_ELEMENT = 0
      NODE_TEXT = 1
      NODE_COMMENT = 2
      NODE_CDATA = 3
      NODE_PI = 4
      NODE_DOCTYPE = 5
      NODE_ATTRIBUTE = 6

      C14N_1_0 = 0
      C14N_1_1 = 1

      C14N_MODE_CANONICAL = 0
      C14N_MODE_EXCLUSIVE = 1

      TRAVERSE_PRE_ORDER = 0
      TRAVERSE_POST_ORDER = 1

      LEPTRIS_PARSE_DEFAULT = 0
      LEPTRIS_PARSE_DROP_WS_TEXT = 1

      # Reads an libleptris-owned char* result and frees it as one unit,
      # so a call site can neither leak nor double-free.
      def self.read_owned_string(ptr)
        return "" if ptr.nil? || ptr.null?
        ptr.read_string.tap { leptris_free_string(ptr) }
      end

      # Single status seam: turns a C status code into a Ruby error.
      def self.check_status(status)
        unless status == LEPTRIS_OK
          raise Leptris::XML::Error, leptris_status_string(status)
        end
        status
      end
    end
  end
end
