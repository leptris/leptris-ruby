# frozen_string_literal: true

require "ffi"

module Taurus
  module XML
    module FFI
      extend ::FFI::Library

      ffi_lib [
        ENV["TAURUS_LIB_PATH"],
        File.expand_path("../../libtaurus.dylib", __dir__),
        File.expand_path("../../libtaurus.so", __dir__),
        "/usr/local/lib/libtaurus.dylib",
        "/usr/local/lib/libtaurus.so",
        "taurus",
      ].compact

      typedef :pointer, :taurus_document
      typedef :pointer, :taurus_element
      typedef :pointer, :taurus_node_ref
      typedef :pointer, :taurus_attribute
      typedef :pointer, :taurus_doctype
      typedef :pointer, :taurus_xpath_result
      typedef :pointer, :taurus_xpath_var_set
      typedef :pointer, :taurus_sax_parser
      typedef :int, :taurus_status

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

      attach_function :taurus_version, [], :string
      attach_function :taurus_version_components, [:pointer, :pointer, :pointer], :void

      attach_function :taurus_parse_string,
        [:string, :size_t, :pointer], :taurus_document
      attach_function :taurus_parse_string_inplace,
        [:pointer, :size_t, :pointer], :taurus_document
      attach_function :taurus_parse_string_with_encoding,
        [:string, :size_t, :pointer], :taurus_document
      attach_function :taurus_parse_file,
        [:string, :pointer], :taurus_document
      attach_function :taurus_load_file,
        [:string, :pointer], :pointer
      attach_function :taurus_document_free,
        [:taurus_document], :void
      attach_function :taurus_document_root,
        [:taurus_document], :taurus_element
      attach_function :taurus_document_encoding,
        [:taurus_document], :string
      attach_function :taurus_document_finalize_strings,
        [:taurus_document], :int
      attach_function :taurus_document_adopt_child,
        [:taurus_document, :taurus_document], :void
      attach_function :taurus_document_set_strict,
        [:taurus_document, :int], :taurus_status
      attach_function :taurus_document_get_strict,
        [:taurus_document], :int
      attach_function :taurus_document_freeze,
        [:taurus_document], :taurus_status
      attach_function :taurus_document_is_frozen,
        [:taurus_document], :int
      attach_function :taurus_set_strict_mode, [:int], :void
      attach_function :taurus_get_strict_mode, [], :int
      attach_function :taurus_set_max_depth, [:int], :void
      attach_function :taurus_get_max_depth, [], :int
      attach_function :taurus_xinclude_process,
        [:taurus_document, :string], :taurus_status
      attach_function :taurus_xinclude_is_include_element,
        [:taurus_element], :int
      attach_function :taurus_xinclude_is_fallback_element,
        [:taurus_element], :int
      attach_function :taurus_xinclude_get_href, [:taurus_element], :string
      attach_function :taurus_xinclude_get_parse, [:taurus_element], :string
      attach_function :taurus_xinclude_get_xpointer, [:taurus_element], :string
      # taurus_xinclude_get_encoding is declared in taurus.h but not exported
      # from the v0.4.4 dylib (likely same visibility bug as the serialize
      # functions; see upstream issue #166). Re-add once #173 / v0.4.5 ships.

      attach_function :taurus_node_get_type,
        [:taurus_node_ref], :int
      attach_function :taurus_node_first_child,
        [:taurus_node_ref], :taurus_node_ref
      attach_function :taurus_node_last_child,
        [:taurus_node_ref], :taurus_node_ref
      attach_function :taurus_node_next_sibling,
        [:taurus_node_ref], :taurus_node_ref
      attach_function :taurus_node_previous_sibling,
        [:taurus_node_ref], :taurus_node_ref
      attach_function :taurus_node_child_count,
        [:taurus_node_ref], :size_t
      attach_function :taurus_node_as_element,
        [:taurus_node_ref], :taurus_element
      attach_function :taurus_element_as_node,
        [:taurus_element], :taurus_node_ref
      attach_function :taurus_node_get_binding_wrapper,
        [:taurus_node_ref], :pointer
      attach_function :taurus_node_set_binding_wrapper,
        [:taurus_node_ref, :pointer], :void
      attach_function :taurus_node_parent,
        [:taurus_node_ref], :taurus_element
      attach_function :taurus_node_unlink,
        [:taurus_node_ref], :taurus_status
      attach_function :taurus_node_line,
        [:taurus_node_ref], :int
      attach_function :taurus_node_compare,
        [:taurus_node_ref, :taurus_node_ref], :int
      attach_function :taurus_node_traverse,
        [:taurus_node_ref, :int, :pointer, :pointer], :int

      attach_function :taurus_text_node_get_content,
        [:taurus_node_ref], :string
      attach_function :taurus_comment_node_get_content,
        [:taurus_node_ref], :string
      attach_function :taurus_cdata_node_get_content,
        [:taurus_node_ref], :string
      attach_function :taurus_pi_node_get_target,
        [:taurus_node_ref], :string
      attach_function :taurus_pi_node_get_data,
        [:taurus_node_ref], :string
      attach_function :taurus_text_node_create,
        [:taurus_document, :string], :taurus_node_ref
      attach_function :taurus_comment_node_create,
        [:taurus_document, :string], :taurus_node_ref
      attach_function :taurus_cdata_node_create,
        [:taurus_document, :string], :taurus_node_ref
      attach_function :taurus_pi_node_create,
        [:taurus_document, :string, :string], :taurus_node_ref
      attach_function :taurus_text_node_set_content,
        [:taurus_node_ref, :string], :taurus_status
      attach_function :taurus_comment_node_set_content,
        [:taurus_node_ref, :string], :taurus_status
      attach_function :taurus_cdata_node_set_content,
        [:taurus_node_ref, :string], :taurus_status
      attach_function :taurus_pi_node_set_target,
        [:taurus_node_ref, :string], :taurus_status
      attach_function :taurus_pi_node_set_data,
        [:taurus_node_ref, :string], :taurus_status

      attach_function :taurus_element_name,
        [:taurus_element], :string
      attach_function :taurus_element_text,
        [:taurus_element], :string
      attach_function :taurus_element_text_int,
        [:taurus_element, :int], :int
      attach_function :taurus_element_text_uint,
        [:taurus_element, :uint], :uint
      attach_function :taurus_element_text_double,
        [:taurus_element, :double], :double
      attach_function :taurus_element_text_float,
        [:taurus_element, :float], :float
      attach_function :taurus_element_text_bool,
        [:taurus_element, :int], :int
      attach_function :taurus_element_attribute,
        [:taurus_element, :string], :string
      attach_function :taurus_element_attribute_string,
        [:taurus_element, :string, :string], :string
      attach_function :taurus_element_attribute_int,
        [:taurus_element, :string, :int], :int
      attach_function :taurus_element_attribute_uint,
        [:taurus_element, :string, :uint], :uint
      attach_function :taurus_element_attribute_double,
        [:taurus_element, :string, :double], :double
      attach_function :taurus_element_attribute_float,
        [:taurus_element, :string, :float], :float
      attach_function :taurus_element_attribute_bool,
        [:taurus_element, :string, :int], :int
      # taurus_element_has_attribute is declared in taurus.h but not exported
      # from the v0.4.4 dylib (likely visibility bug; see upstream #166).
      # Ruby-level Element#key? will emulate via attribute lookup.
      attach_function :taurus_element_attribute_count,
        [:taurus_element], :size_t
      attach_function :taurus_element_attribute_name_at,
        [:taurus_element, :size_t], :string
      attach_function :taurus_element_attribute_value_at,
        [:taurus_element, :size_t], :string
      attach_function :taurus_element_remove_all_attributes,
        [:taurus_element], :taurus_status

      attach_function :taurus_element_child_count,
        [:taurus_element], :size_t
      attach_function :taurus_element_child,
        [:taurus_element, :size_t], :taurus_element
      attach_function :taurus_element_parent,
        [:taurus_element], :taurus_element
      attach_function :taurus_element_root,
        [:taurus_element], :taurus_element
      attach_function :taurus_element_child_value,
        [:taurus_element], :string
      attach_function :taurus_element_hash_value,
        [:taurus_element], :size_t
      attach_function :taurus_element_find_child,
        [:taurus_element, :string], :taurus_element
      attach_function :taurus_element_find_child_by_attr,
        [:taurus_element, :string, :string, :string], :taurus_element
      attach_function :taurus_element_next_sibling,
        [:taurus_element, :string], :taurus_element
      attach_function :taurus_element_previous_sibling,
        [:taurus_element, :string], :taurus_element
      attach_function :taurus_element_first_child,
        [:taurus_element, :string], :taurus_element
      attach_function :taurus_element_last_child,
        [:taurus_element, :string], :taurus_element
      attach_function :taurus_element_first_child_any,
        [:taurus_element], :taurus_element
      attach_function :taurus_element_last_child_any,
        [:taurus_element], :taurus_element
      attach_function :taurus_element_next_sibling_any,
        [:taurus_element], :taurus_element
      attach_function :taurus_element_previous_sibling_any,
        [:taurus_element], :taurus_element

      attach_function :taurus_element_create,
        [:taurus_document, :string], :taurus_element
      attach_function :taurus_element_set_name,
        [:taurus_element, :string], :taurus_status
      attach_function :taurus_element_set_text,
        [:taurus_element, :string], :taurus_status
      attach_function :taurus_element_set_attribute,
        [:taurus_element, :string, :string], :taurus_status
      attach_function :taurus_element_set_attribute_bool,
        [:taurus_element, :string, :int], :taurus_status
      attach_function :taurus_element_set_attribute_double,
        [:taurus_element, :string, :double], :taurus_status
      attach_function :taurus_element_set_attribute_float,
        [:taurus_element, :string, :float], :taurus_status
      attach_function :taurus_element_set_attribute_int,
        [:taurus_element, :string, :int], :taurus_status
      attach_function :taurus_element_set_attribute_uint,
        [:taurus_element, :string, :uint], :taurus_status
      attach_function :taurus_element_remove_attribute,
        [:taurus_element, :string], :taurus_status
      attach_function :taurus_element_append_child,
        [:taurus_element, :taurus_element], :taurus_status
      attach_function :taurus_element_prepend_child,
        [:taurus_element, :taurus_element], :taurus_status
      attach_function :taurus_element_insert_before,
        [:taurus_element, :taurus_element], :taurus_status
      attach_function :taurus_element_insert_after,
        [:taurus_element, :taurus_element], :taurus_status
      attach_function :taurus_element_remove_child,
        [:taurus_element, :taurus_element], :taurus_status
      attach_function :taurus_element_remove_children,
        [:taurus_element], :taurus_status
      attach_function :taurus_element_append_copy,
        [:taurus_element, :taurus_element], :taurus_element
      attach_function :taurus_element_prepend_copy,
        [:taurus_element, :taurus_element], :taurus_element
      attach_function :taurus_element_insert_copy_before,
        [:taurus_element, :taurus_element], :taurus_element
      attach_function :taurus_element_insert_copy_after,
        [:taurus_element, :taurus_element], :taurus_element

      attach_function :taurus_element_copy,
        [:taurus_element, :taurus_document], :taurus_element
      attach_function :taurus_document_copy,
        [:taurus_document], :taurus_document
      attach_function :taurus_node_get_xpath,
        [:taurus_node_ref], :pointer
      attach_function :taurus_parse_fragment,
        [:string, :size_t, :taurus_document, :pointer], :taurus_element

      attach_function :taurus_element_namespace,
        [:taurus_element], :string
      attach_function :taurus_element_namespace_for_prefix,
        [:taurus_element, :string], :string
      attach_function :taurus_element_namespace_count,
        [:taurus_element], :size_t
      attach_function :taurus_element_namespace_decl_prefix,
        [:taurus_element, :size_t], :string
      attach_function :taurus_element_namespace_decl_uri,
        [:taurus_element, :size_t], :string
      attach_function :taurus_element_add_namespace_definition,
        [:taurus_element, :string, :string], :taurus_status
      attach_function :taurus_element_set_default_namespace,
        [:taurus_element, :string], :taurus_status
      attach_function :taurus_element_remove_namespace_definition,
        [:taurus_element, :string], :taurus_status
      attach_function :taurus_namespace_uri, [:string], :string
      attach_function :taurus_namespace_prefix, [:string], :string

      attach_function :taurus_xpath_eval,
        [:taurus_document, :taurus_element, :string], :taurus_xpath_result
      attach_function :taurus_xpath_eval_with_vars,
        [:taurus_document, :string, :taurus_xpath_var_set], :taurus_xpath_result
      attach_function :taurus_xpath_eval_with_vars_context,
        [:taurus_document, :taurus_element, :string, :taurus_xpath_var_set],
        :taurus_xpath_result
      attach_function :taurus_xpath_result_type,
        [:taurus_xpath_result], :int
      attach_function :taurus_xpath_result_count,
        [:taurus_xpath_result], :size_t
      attach_function :taurus_xpath_result_get,
        [:taurus_xpath_result, :size_t], :taurus_element
      attach_function :taurus_xpath_result_get_nodes,
        [:taurus_xpath_result, :pointer, :size_t], :size_t
      attach_function :taurus_xpath_result_boolean,
        [:taurus_xpath_result], :int
      attach_function :taurus_xpath_result_number,
        [:taurus_xpath_result], :double
      attach_function :taurus_xpath_result_string,
        [:taurus_xpath_result], :pointer
      attach_function :taurus_xpath_result_free,
        [:taurus_xpath_result], :void
      attach_function :taurus_xpath_function_supported, [:string], :int
      attach_function :taurus_xpath_supported_functions, [], :pointer

      attach_function :taurus_xpath_variable_set_new,
        [], :taurus_xpath_var_set
      attach_function :taurus_xpath_variable_set_free,
        [:taurus_xpath_var_set], :void
      attach_function :taurus_xpath_variable_set_boolean,
        [:taurus_xpath_var_set, :string, :int], :taurus_status
      attach_function :taurus_xpath_variable_set_number,
        [:taurus_xpath_var_set, :string, :double], :taurus_status
      attach_function :taurus_xpath_variable_set_string,
        [:taurus_xpath_var_set, :string, :string], :taurus_status

      attach_function :taurus_sax_parse,
        [:string, :size_t, :pointer, :pointer], :int
      attach_function :taurus_sax_parser_create,
        [:pointer, :pointer], :taurus_sax_parser
      attach_function :taurus_sax_parser_feed,
        [:taurus_sax_parser, :string, :size_t, :int], :int
      attach_function :taurus_sax_parser_free,
        [:taurus_sax_parser], :void
      attach_function :taurus_sax_parser_set_streaming,
        [:taurus_sax_parser, :int], :int

      attach_function :taurus_document_serialize,
        [:taurus_document, :pointer], :pointer
      attach_function :taurus_element_serialize,
        [:taurus_element, :pointer], :pointer
      attach_function :taurus_document_save_file,
        [:taurus_document, :string, :pointer], :taurus_status
      attach_function :taurus_c14n_canonicalize,
        [:taurus_document, :int, :int], :pointer
      attach_function :taurus_c14n_canonicalize_subtree,
        [:taurus_element, :int, :int], :pointer
      attach_function :taurus_c14n_canonicalize_ex,
        [:taurus_document, :int, :int, :pointer, :int], :pointer
      attach_function :taurus_c14n_canonicalize_subtree_ex,
        [:taurus_element, :int, :int, :pointer, :int], :pointer

      attach_function :taurus_document_internal_subset,
        [:taurus_document], :taurus_doctype
      attach_function :taurus_doctype_get_name,
        [:taurus_doctype], :string
      attach_function :taurus_doctype_get_root_name,
        [:taurus_doctype], :string
      attach_function :taurus_doctype_get_public_id,
        [:taurus_doctype], :string
      attach_function :taurus_doctype_get_system_id,
        [:taurus_doctype], :string
      attach_function :taurus_doctype_get_internal_subset,
        [:taurus_doctype], :string

      attach_function :taurus_free_string, [:pointer], :void
      attach_function :taurus_explicit_cleanup, [], :void
      attach_function :taurus_set_memory_management_functions,
        [:pointer, :pointer], :void
      attach_function :taurus_get_memory_allocation_function, [], :pointer
      attach_function :taurus_get_memory_deallocation_function, [], :pointer
      attach_function :taurus_document_set_allocators,
        [:taurus_document, :pointer, :pointer], :taurus_status
      attach_function :taurus_status_string, [:taurus_status], :string

      TAURUS_OK = 0
      TAURUS_ERROR_MEMORY = -1
      TAURUS_ERROR_PARSE = -2
      TAURUS_ERROR_XPATH = -3
      TAURUS_ERROR_NULL_ARG = -4
      TAURUS_ERROR_INVALID_ARG = -5
      TAURUS_ERROR_NOT_FOUND = -6
      TAURUS_ERROR_IO = -7
      TAURUS_ERROR_NOT_IMPLEMENTED = -8

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
    end
  end
end
