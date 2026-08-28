# frozen_string_literal: true

require "ffi"

module Leptris
  module XML
    module FFI
      extend ::FFI::Library

      # Issue leptris-ruby#49: name the remedy when the library is
      # missing (ruby-platform gem without a vendored libleptris).
      begin
        ffi_lib [
          ENV["LEPTRIS_LIB_PATH"],
          File.expand_path("../../libleptris.dylib", __dir__),
          File.expand_path("../../libleptris.so", __dir__),
          File.expand_path("../../libleptris.dll", __dir__),
          "/usr/local/lib/libleptris.dylib",
          "/usr/local/lib/libleptris.so",
          "leptris",
        ].compact
      rescue LoadError => e
        raise LoadError, <<~MSG
          leptris: cannot load the vendored libleptris library.
          You may have installed the ruby-platform variant of this
          gem (#{Gem.loaded_specs["leptris"]&.full_name rescue "unknown"}),
          which does not vendor the native library. Fix:

            bundle update leptris        # force platform gems
            # or: gem install leptris --platform ruby is unsupported
            # or: set LEPTRIS_LIB_PATH=/path/to/libleptris.so

          Original error: #{e.message}
        MSG
      end

      typedef :pointer, :leptris_document
      typedef :pointer, :leptris_element
      typedef :pointer, :leptris_node_ref
      typedef :pointer, :leptris_attribute
      typedef :pointer, :leptris_doctype
      typedef :pointer, :leptris_xpath_result
      typedef :pointer, :leptris_xpath_ns_set
      typedef :pointer, :leptris_xpath_compiled
      typedef :pointer, :leptris_xslt
      typedef :pointer, :leptris_sax_recorder
      typedef :pointer, :leptris_pull_parser
      typedef :pointer, :leptris_iterparse
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

      # Mirrors LeptrisParseOptions (libleptris >= 1.9.0 carries the
      # recover field; earlier fields unchanged since v1.6.0).
      class ParseOptionsStruct < ::FFI::Struct
        layout \
          :flags, :int,
          :strict_mode, :int,
          :max_depth, :int,
          :recover, :int
      end

      # LeptrisSaxEventRecord (types.h, issue #585): fixed layout the
      # header explicitly freezes for FFI mirrors. Strings are NOT
      # inline — name/text/attrs slice the recorder's arena.
      class SaxEventRecord < ::FFI::Struct
        layout :kind, :uint8,
               :reserved, [:uint8, 7],
               :name_off, :uint32, :name_len, :uint32,
               :text_off, :uint32, :text_len, :uint32,
               :attrs_off, :uint32, :attr_count, :uint32,
               :line, :uint32, :column, :uint32
      end

      SAX_EVENT_START_DOCUMENT = 0
      SAX_EVENT_END_DOCUMENT   = 1
      SAX_EVENT_START_ELEMENT  = 2
      SAX_EVENT_END_ELEMENT    = 3
      SAX_EVENT_CHARACTERS     = 4
      SAX_EVENT_COMMENT        = 5
      SAX_EVENT_CDATA          = 6
      SAX_EVENT_PI             = 7
      SAX_EVENT_START_PREFIX   = 8
      SAX_EVENT_END_PREFIX     = 9
      SAX_EVENT_ERROR          = 10

      ITERPARSE_TOP_LEVEL      = 0
      ITERPARSE_FULL_DOCUMENT  = 1

      # struct LeptrisPullEvent (leptris/sax.h): FFI::Struct derives
      # the field offsets from the layout, so ABI changes are a
      # one-line edit here instead of silent offset drift in callers.
      class PullEventStruct < ::FFI::Struct
        layout \
          :type, :int,
          :name, :pointer,
          :text, :pointer,
          :text_len, :size_t
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
      attach_function :leptris_document_create,
        [], :leptris_document
      attach_function :leptris_document_set_root,
        [:leptris_document, :leptris_element], :leptris_status
      attach_function :leptris_document_root,
        [:leptris_document], :leptris_element
      # The document node — navigation head over the whole tree
      # chain [prolog comments/PIs, root, epilog...] (libleptris
      # 1.9.7, upstream #580; the libxml2 model).
      attach_function :leptris_document_node,
        [:leptris_document], :leptris_node_ref
      # Document-level PIs (v1.6.0): not tree nodes — enumerate via
      # these accessors only.
      attach_function :leptris_document_pi_count,
        [:leptris_document], :size_t
      attach_function :leptris_document_pi_target,
        [:leptris_document, :size_t], :string
      attach_function :leptris_document_pi_data,
        [:leptris_document, :size_t], :string
      attach_function :leptris_document_add_pi,
        [:leptris_document, :string, :string], :pointer
      # Document-level comments (libleptris 1.9.3, #578): parsed
      # <!-- ... --> outside the root, prolog then epilog, in
      # document order. Read-only surface (no add_comment yet).
      attach_function :leptris_document_comment_count,
        [:leptris_document], :size_t
      attach_function :leptris_document_comment_content,
        [:leptris_document, :size_t], :string
      # Options-struct parse (v1.6.0): supersedes the flags variants;
      # the flags path remains bound for compatibility.
      attach_function :leptris_parse_string_ex,
        [:string, :size_t, :pointer, :pointer], :leptris_document
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
      attach_function :leptris_xinclude_get_encoding, [:leptris_element], :string

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
      # libleptris 1.7.0: all-kind child batch — out_nodes=NULL is a
      # count-only query returning the TOTAL across every child kind.
      attach_function :leptris_node_children,
        [:leptris_node_ref, :pointer, :size_t], :size_t
      # Element-only batch; mirror-only — fetch_children rides the
      # all-kind node_children above.
      attach_function :leptris_element_children,
        [:leptris_element, :pointer, :size_t], :size_t
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
      attach_function :leptris_element_has_attribute,
        [:leptris_element, :string], :int
      # libleptris 1.8.0: expanded-name lookup — (uri, local) with
      # XML Namespaces 1.0 semantics; NULL/"" uri matches only
      # no-namespace attributes, xmlns declarations never match.
      attach_function :leptris_element_attribute_ns,
        [:leptris_element, :string, :string], :string
      attach_function :leptris_element_has_attribute_ns,
        [:leptris_element, :string, :string], :int
      # libleptris 1.8.0: per-attribute prefix (name-derived) and
      # namespace URI (resolved through the owning element's
      # in-scope declarations at read time).
      attach_function :leptris_attribute_prefix,
        [:leptris_attribute], :string
      attach_function :leptris_attribute_namespace_uri,
        [:leptris_attribute], :string
      attach_function :leptris_element_first_attribute,
        [:leptris_element], :leptris_attribute
      attach_function :leptris_attribute_next,
        [:leptris_attribute], :leptris_attribute
      attach_function :leptris_attribute_get_name,
        [:leptris_attribute], :string
      attach_function :leptris_attribute_get_value,
        [:leptris_element, :leptris_attribute], :string
      attach_function :leptris_element_prefix,
        [:leptris_element], :string
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
      # Union semantics (NodeSet#xpath): N contexts, ONE call — the
      # engine merges the per-context results into a de-duplicated,
      # document-ordered nodeset (libleptris 1.9.7, upstream #589).
      attach_function :leptris_xpath_eval_nodeset,
        [:leptris_document, :pointer, :size_t, :string], :leptris_xpath_result
      attach_function :leptris_xpath_compiled_eval_nodeset,
        [:leptris_document, :pointer, :size_t, :leptris_xpath_compiled],
        :leptris_xpath_result
      attach_function :leptris_xpath_eval_with_vars_context,
        [:leptris_document, :leptris_element, :string, :leptris_xpath_var_set],
        :leptris_xpath_result
      attach_function :leptris_xpath_result_type,
        [:leptris_xpath_result], :int
      attach_function :leptris_xpath_result_count,
        [:leptris_xpath_result], :size_t
      # Mixed nodesets (v1.1.0): unlike result_get (elements only),
      # get_node returns the node whatever its kind; node_kind reports
      # which (element / synthetic attribute / text / other).
      attach_function :leptris_xpath_result_node_kind,
        [:leptris_xpath_result, :size_t], :int
      # Pre-_ex variants, superseded by xpath_result_get_nodes_ex /
      # xpath_result_get_node; mirror-only (ADR 0001).
      attach_function :leptris_xpath_result_get,
        [:leptris_xpath_result, :size_t], :leptris_element
      attach_function :leptris_xpath_result_get_nodes,
        [:leptris_xpath_result, :pointer, :size_t], :size_t
      attach_function :leptris_xpath_result_get_node,
        [:leptris_xpath_result, :size_t], :leptris_node_ref
      attach_function :leptris_xpath_result_node_name,
        [:leptris_xpath_result, :size_t], :string
      attach_function :leptris_xpath_result_node_value,
        [:leptris_xpath_result, :size_t], :string
      # Document-scoped custom XPath functions. The callback receives
      # (const char* const* args, int argc, void* user_data) and returns
      # a heap string the library frees.
      attach_function :leptris_xpath_register_function,
        [:leptris_document, :string, :pointer, :pointer], :leptris_status
      # v1.3.0: copies ALL node kinds in one call, optionally
      # reporting per-entry kinds.
      attach_function :leptris_xpath_result_get_nodes_ex,
        [:leptris_xpath_result, :pointer, :pointer, :size_t], :size_t
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

      # Namespace-bound XPath (v1.2.0): expression prefixes resolve to
      # caller-supplied URIs regardless of the document's declarations.
      attach_function :leptris_xpath_ns_set_new,
        [], :leptris_xpath_ns_set
      attach_function :leptris_xpath_ns_set_free,
        [:leptris_xpath_ns_set], :void
      # One-call constructor: flat array of 2*pair_count alternating
      # prefix/URI strings.
      # Per-pair add; superseded by ns_set_new_from_pairs (one call);
      # mirror-only (ADR 0001).
      attach_function :leptris_xpath_ns_set_add,
        [:leptris_xpath_ns_set, :string, :string], :leptris_status
      attach_function :leptris_xpath_ns_set_new_from_pairs,
        [:pointer, :size_t], :leptris_xpath_ns_set
      attach_function :leptris_xpath_eval_ns,
        [:leptris_document, :leptris_element, :string, :leptris_xpath_ns_set],
        :leptris_xpath_result
      # Compiled expressions (v1.6.0): parse once, evaluate many.
      attach_function :leptris_xpath_compile,
        [:string], :leptris_xpath_compiled
      attach_function :leptris_xpath_compiled_eval,
        [:leptris_xpath_compiled, :leptris_document, :leptris_element],
        :leptris_xpath_result
      attach_function :leptris_xpath_compiled_eval_ns,
        [:leptris_xpath_compiled, :leptris_document, :leptris_element,
         :leptris_xpath_ns_set], :leptris_xpath_result
      attach_function :leptris_xpath_compiled_eval_vars,
        [:leptris_xpath_compiled, :leptris_document, :leptris_element,
         :leptris_xpath_var_set], :leptris_xpath_result
      # Source text of a compiled expression (owned by the handle).
      attach_function :leptris_xpath_compiled_text,
        [:leptris_xpath_compiled], :string
      attach_function :leptris_xpath_compiled_free,

        [:leptris_xpath_compiled], :void

      attach_function :leptris_sax_parse,
        [:string, :size_t, :pointer, :pointer], :int
      attach_function :leptris_sax_parser_create,
        [:pointer, :pointer], :leptris_sax_parser
      attach_function :leptris_sax_parser_feed,
        [:leptris_sax_parser, :string, :size_t, :int], :int
      # Chunked event recorder (libleptris 1.9.4, #585): buffers
      # events C-side (fixed records + packed arena); the host
      # drains in bulk — callbacks become O(chunks), not O(events).
      attach_function :leptris_sax_recorder_new,
        [], :leptris_sax_recorder
      attach_function :leptris_sax_recorder_feed,
        [:leptris_sax_recorder, :string, :size_t, :int], :int
      attach_function :leptris_sax_recorder_records,
        [:leptris_sax_recorder, :pointer], :pointer
      attach_function :leptris_sax_recorder_arena,
        [:leptris_sax_recorder, :pointer], :pointer
      attach_function :leptris_sax_recorder_free,
        [:leptris_sax_recorder], :void
      attach_function :leptris_sax_parser_free,
        [:leptris_sax_parser], :void
      attach_function :leptris_sax_parser_set_streaming,
        [:leptris_sax_parser, :int], :int

      # Pull parsing (v1.6.0): StAX-style cursor over a document.
      attach_function :leptris_pull_new,
        [:string, :size_t], :leptris_pull_parser
      attach_function :leptris_pull_new_file,
        [:string], :leptris_pull_parser
      attach_function :leptris_pull_next,
        [:leptris_pull_parser], :pointer
      attach_function :leptris_pull_next_batch,
        [:leptris_pull_parser, :pointer, :size_t], :size_t
      attach_function :leptris_pull_attr_count,
        [:leptris_pull_parser], :size_t
      attach_function :leptris_pull_attr_name,
        [:leptris_pull_parser, :size_t], :string
      attach_function :leptris_pull_attr_value,
        [:leptris_pull_parser, :size_t], :string
      attach_function :leptris_pull_attrs,
        [:leptris_pull_parser, :pointer, :size_t], :size_t
      attach_function :leptris_pull_free,
        [:leptris_pull_parser], :void

      # Iterparse (v1.6.0): yields each completed top-level child
      # element; the previous subtree is released on each next call.
      attach_function :leptris_iterparse_new,
        [:string, :size_t], :leptris_iterparse
      attach_function :leptris_iterparse_new_file,
        [:string], :leptris_iterparse
      attach_function :leptris_iterparse_next,
        [:leptris_iterparse], :leptris_element
      # iterparse v2 (libleptris 1.9.4, #586): explicit yield mode
      # (top-level children or full-document post-order), namespace
      # resolution on the last yielded element, error channel.
      attach_function :leptris_iterparse_new_ex,
        [:string, :size_t, :int], :leptris_iterparse
      attach_function :leptris_iterparse_new_file_ex,
        [:string, :int], :leptris_iterparse
      attach_function :leptris_iterparse_ns_count,
        [:leptris_iterparse], :size_t
      attach_function :leptris_iterparse_ns_uri,
        [:leptris_iterparse, :string], :string
      attach_function :leptris_iterparse_error,
        [:leptris_iterparse], :string
      attach_function :leptris_iterparse_free,
        [:leptris_iterparse], :void

      attach_function :leptris_document_serialize,
        [:leptris_document, :pointer], :pointer
      # Deprecated automatic-options alias (header: prefer
      # leptris_document_serialize); mirror-only.
      attach_function :leptris_serialize_document,
        [:leptris_document], :pointer
      # libleptris >= 1.9.0: caller-buffer serialization with options
      # (leptris#541). buf=NULL is a size query; the size-query +
      # fill pair reuses one serialization through a per-document
      # cache invalidated on mutation.
      attach_function :leptris_document_serialize_into,
        [:leptris_document, :pointer, :size_t, :pointer, :pointer], :size_t
      attach_function :leptris_document_get_dtd,
        [:leptris_document], :pointer
      attach_function :leptris_element_serialize,
        [:leptris_element, :pointer], :pointer
      attach_function :leptris_element_serialize_into,
        [:leptris_element, :pointer, :size_t, :pointer, :pointer], :size_t
      attach_function :leptris_document_save_file,
        [:leptris_document, :string, :pointer], :leptris_status
      # XSLT 1.0 engine (libleptris 1.9.1): compile once, apply many.
      attach_function :leptris_xslt_parse,
        [:string, :size_t], :leptris_xslt
      attach_function :leptris_xslt_parse_file,
        [:string], :leptris_xslt
      attach_function :leptris_xslt_free,
        [:leptris_xslt], :void
      # Result tree is a document (free with document_free); errors
      # surface via document_last_error on NULL.
      attach_function :leptris_xslt_apply,
        [:leptris_xslt, :leptris_document], :leptris_document
      # apply + serialize in one call, keeping top-level text nodes
      # and result fragments the tree API would flatten.
      attach_function :leptris_xslt_apply_string,
        [:leptris_xslt, :leptris_document], :pointer
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
      attach_function :leptris_error_message, [:leptris_status], :string
      # Thread-global last-failure position (error.h): companion to
      # leptris_last_error; populated by recover parses (#547).
      attach_function :leptris_last_error_position,
        [:pointer, :pointer], :void
      # Thread-local since v1.3.0; reliable under the
      # one-document-per-thread contract.
      attach_function :leptris_last_error, [], :string
      attach_function :leptris_document_last_error,
        [:leptris_document], :string
      # Optional: release per-thread registry entries when a worker
      # thread exits (long-lived threads never need it).
      attach_function :leptris_thread_cleanup, [], :void
      # First-party EXSLT-style extension pack (str:/set:/math:),
      # registered natively on one document.
      attach_function :leptris_exslt_enable,
        [:leptris_document], :leptris_status

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

      XPATH_NODE_ELEMENT = 0
      XPATH_NODE_ATTRIBUTE = 1
      XPATH_NODE_TEXT = 2
      XPATH_NODE_OTHER = 3

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

      PULL_START_ELEMENT = 0
      PULL_END_ELEMENT   = 1
      PULL_TEXT          = 2
      PULL_COMMENT       = 3
      PULL_CDATA         = 4
      PULL_PI            = 5
      PULL_END_DOCUMENT  = 6
      PULL_ERROR         = 7

      LEPTRIS_PARSE_DEFAULT = 0
      LEPTRIS_PARSE_DROP_WS_TEXT = 1

      # The headers' contract is UTF-8 for every C string, but FFI's
      # read_string hands back ASCII-8BIT — the platform default
      # leaks through the seam. Every string-returning attached
      # function this binding CALLS is wrapped here so its result
      # arrives as UTF-8; mirror-only attachments stay raw (add the
      # name here when a call site starts using its string).
      UTF8_RETURNS = %i[
        leptris_version
        leptris_status_string leptris_last_error
        leptris_document_last_error leptris_document_encoding
        leptris_document_pi_target leptris_document_pi_data
        leptris_document_comment_content
        leptris_element_name leptris_element_text leptris_element_prefix
        leptris_element_namespace
        leptris_element_attribute leptris_element_attribute_ns
        leptris_attribute_get_name leptris_attribute_get_value
        leptris_attribute_namespace_uri
        leptris_element_namespace_decl_prefix
        leptris_element_namespace_decl_uri
        leptris_text_node_get_content leptris_comment_node_get_content
        leptris_cdata_node_get_content
        leptris_pi_node_get_target leptris_pi_node_get_data
        leptris_pull_attr_name leptris_pull_attr_value
      ].freeze
      private_constant :UTF8_RETURNS

      UTF8_RETURNS.each do |name|
        raw = method(name)
        define_singleton_method(name) do |*args|
          str = raw.call(*args)
          str.nil? ? nil : str.force_encoding(Encoding::UTF_8)
        end
      end

      # Reads an libleptris-owned char* result and frees it as one unit,
      # so a call site can neither leak nor double-free.
      def self.read_owned_string(ptr)
        return "" if ptr.nil? || ptr.null?
        ptr.read_string.tap { leptris_free_string(ptr) }
          .force_encoding(Encoding::UTF_8)
      end

      # Single status seam: turns a C status code into a Ruby error,
      # appending the library's last-error detail when present. The
      # detail is a library-global string, so it can only be treated
      # as best-effort context.
      def self.check_status(status)
        unless status == LEPTRIS_OK
          raise Leptris::XML::Error, status_message(status)
        end
        status
      end

      def self.status_message(status)
        base = leptris_status_string(status).to_s
        detail = leptris_last_error.to_s
        detail.empty? ? base : "#{base} (#{detail})"
      end

      # Namespace-binding lifecycle, written once: flatten the
      # prefix/URI hash into the alternating CStringArray wire
      # format, build the caller-owned set, yield it, free it under
      # all outcomes. Every eval variant uses this; none of them
      # knows how a set is born or dies.
      def self.with_ns_set(hash)
        flat = hash.flat_map { |prefix, uri| [prefix.to_s, uri.to_s] }
        buffer, _anchors = Leptris::XML::CStringArray.to_c(flat)
        set = leptris_xpath_ns_set_new_from_pairs(buffer, flat.length / 2)
        if set.null?
          raise Leptris::XML::Error,
            "leptris_xpath_ns_set_new_from_pairs failed"
        end
        begin
          yield set
        ensure
          leptris_xpath_ns_set_free(set)
        end
      end

      # Caller-buffer serialization cycle: size query (buf=NULL),
      # allocate exactly, fill, read. Since libleptris 1.9.0 the
      # pair reuses one serialization through the per-document
      # cache. +ffi_function+ is leptris_document_serialize_into or
      # leptris_element_serialize_into. The buffer holds the
      # serialization + NUL and XML output is NUL-free, so the
      # bounded read is exact.
      def self.serialize_into_string(ffi_function, c_ptr, options)
        need = ffi_function.call(c_ptr, nil, 0, nil, options)
        return "" if need.zero?
        buffer = ::FFI::MemoryPointer.new(:char, need)
        begin
          ffi_function.call(c_ptr, buffer, need, nil, options)
          buffer.read_string
        ensure
          buffer.free
        end
      end

      # All-kind child handle batch (libleptris 1.7.0). Opportunistic
      # single dispatch: the C call copies up to the capacity handed
      # it and returns what fit, so the count query is paid only when
      # the buffer fills exactly (a possible truncation) — families
      # that fit the scratch buffer cost ONE dispatch, not two.
      FETCH_INITIAL = 32
      private_constant :FETCH_INITIAL

      def self.fetch_children(c_ptr)
        scratch = (Thread.current[:leptris_scratch] ||= {})
        buffer = scratch[:pointers]
        if buffer.nil?
          buffer = scratch[:pointers] =
            ::FFI::MemoryPointer.new(:pointer, FETCH_INITIAL)
        end
        cap = buffer.size / PTR_BYTES
        copied = leptris_node_children(c_ptr, buffer, cap)
        if copied == cap
          total = leptris_node_children(c_ptr, nil, 0)
          if total > cap
            buffer.free
            buffer = scratch[:pointers] =
              ::FFI::MemoryPointer.new(:pointer, total)
            copied = leptris_node_children(c_ptr, buffer, total)
          end
        end
        buffer.get_array_of_pointer(0, copied)
      end

      # XPath result-set batch (leptris_xpath_result_get_nodes_ex):
      # the call fills out_kinds in the 4-value XPATH_NODE space
      # (ELEMENT/ATTRIBUTE/TEXT/OTHER). ELEMENT is the only value
      # that maps unambiguously — XPath's data model reports CDATA
      # as TEXT, so a TEXT hint cannot distinguish Text from CDATA
      # (different content getters) — everything else falls back to
      # get_type in the wrapper. Returns [pointers, element_hints].
      XPATH_KIND_HINT = { XPATH_NODE_ELEMENT => NODE_ELEMENT }.freeze

      def self.fetch_result_nodes(result_ptr, count)
        return [[], nil] if count.zero?
        buffer = scratch_pointers(count)
        kinds = scratch_ints(count)
        copied = leptris_xpath_result_get_nodes_ex(
          result_ptr, buffer, kinds, count)
        hints = kinds.get_array_of_int(0, copied)
          .map { |k| XPATH_KIND_HINT[k] }
        [buffer.get_array_of_pointer(0, copied), hints]
      end

      # Fragment parse with the status out-param read: returns
      # [document-or-fragment pointer, status].
      def self.parse_fragment_with_status(xml, document_ptr)
        status = ::FFI::MemoryPointer.new(:int)
        raw = leptris_parse_fragment(
          xml, xml.bytesize, document_ptr, status)
        [raw, status.read_int]
      end

      # Thread-local scratch buffers for batch handle fetches (round
      # XX): the per-call MemoryPointer new/free was pure cold-path
      # overhead — two allocations and a GC visit per children() /
      # result-set batch, ~15% of a cold full-tree walk between
      # 1.9.1 and 1.9.24. The buffers grow to the largest request
      # seen (bounded by the widest element or result set) and are
      # reused. Safe: no Ruby reentrancy during the C call, and
      # per-thread storage keeps concurrent fetches independent.
      # Never freed — a few KB pinned per thread.
      PTR_BYTES = ::FFI.type_size(:pointer)
      private_constant :PTR_BYTES
      INT_BYTES = ::FFI.type_size(:int)
      private_constant :INT_BYTES

      def self.scratch_pointers(count)
        scratch = (Thread.current[:leptris_scratch] ||= {})
        ptr = scratch[:pointers]
        if ptr.nil? || ptr.size / PTR_BYTES < count
          ptr&.free
          ptr = scratch[:pointers] = ::FFI::MemoryPointer.new(:pointer, count)
        end
        ptr
      end

      def self.scratch_ints(count)
        scratch = (Thread.current[:leptris_scratch] ||= {})
        ptr = scratch[:ints]
        if ptr.nil? || ptr.size / INT_BYTES < count
          ptr&.free
          ptr = scratch[:ints] = ::FFI::MemoryPointer.new(:int, count)
        end
        ptr
      end

      # Pull-event staging block for leptris_pull_next_batch (the
      # #589 bulk transport): LeptrisPullEvent records, stride from
      # the struct layout that mirrors the ABI.
      def self.scratch_events(count)
        need = count * PullEventStruct.size
        scratch = (Thread.current[:leptris_scratch] ||= {})
        ptr = scratch[:pull_events]
        if ptr.nil? || ptr.size < need
          ptr&.free
          ptr = scratch[:pull_events] = ::FFI::MemoryPointer.new(need)
        end
        ptr
      end
    end
  end
end
