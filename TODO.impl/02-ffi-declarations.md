# TODO 2 — FFI declarations: complete libleptris v0.4.2 public API

## Goal

Create `lib/leptris/xml/ffi.rb` that attaches to EVERY public function
in libleptris v0.4.2 via the `ffi` gem. This is the single source of
truth for the C ↔ Ruby boundary.

## Library loading

```ruby
module Leptris
  module XML
    module FFI
      extend ::FFI

      ffi_lib [
        ENV['LEPTRIS_LIB_PATH'],
        'leptris',
        '/usr/local/lib/libleptris.dylib',
        '/usr/local/lib/libleptris.so',
        File.expand_path('../../../build/src/libleptris.dylib', __dir__),
        File.expand_path('../../../build/src/libleptris.so', __dir__),
      ].compact
    end
  end
end
```

## Opaque type declarations

```ruby
typedef :pointer, :document
typedef :pointer, :element
typedef :pointer, :node_ref
typedef :pointer, :xpath_result
typedef :pointer, :sax_parser
typedef :pointer, :attribute
```

## Complete function list (attach all of these)

Source: `src/include/leptris/types.h`, `src/include/leptris.h`, and
`src/include/leptris/*.h`.

### Version
```ruby
attach_function :leptris_version, [], :string
```

### Document lifecycle
```ruby
attach_function :leptris_parse_string, [:string, :size_t, :pointer], :document
attach_function :leptris_document_free, [:document], :void
attach_function :leptris_document_root, [:document], :element
attach_function :leptris_document_serialize, [:document, :pointer], :pointer
attach_function :leptris_document_set_strict, [:document, :int], :void
attach_function :leptris_xinclude_process, [:document, :string], :int
```

### Node access
```ruby
attach_function :leptris_node_get_type, [:node_ref], :int
attach_function :leptris_node_first_child, [:node_ref], :node_ref
attach_function :leptris_node_next_sibling, [:node_ref], :node_ref
attach_function :leptris_node_previous_sibling, [:node_ref], :node_ref
attach_function :leptris_node_child_count, [:node_ref], :size_t
attach_function :leptris_node_as_element, [:node_ref], :element
attach_function :leptris_element_as_node, [:element], :node_ref
attach_function :leptris_element_first_child_any, [:element], :element
```

### Element queries
```ruby
attach_function :leptris_element_name, [:element], :string
attach_function :leptris_element_text, [:element], :string
attach_function :leptris_element_attribute, [:element, :string, :string], :string
attach_function :leptris_element_attribute_count, [:element], :size_t
attach_function :leptris_element_first_attribute, [:element], :pointer
attach_function :leptris_element_parent, [:element], :element
attach_function :leptris_element_next_sibling_any, [:element], :element
attach_function :leptris_element_get_namespace_uri, [:element], :string
attach_function :leptris_element_get_prefix, [:element], :string
attach_function :leptris_element_get_name, [:element], :string
```

### Element mutation
```ruby
attach_function :leptris_element_set_name, [:element, :string], :void
attach_function :leptris_element_set_attribute, [:element, :string, :string], :void
attach_function :leptris_element_remove_attribute, [:element, :string], :void
attach_function :leptris_element_append_child, [:element, :element], :int
attach_function :leptris_element_create_child, [:element, :string], :element
attach_function :leptris_element_set_text, [:element, :string], :void
attach_function :leptris_element_remove_child, [:element, :element], :void
```

### Element creation
```ruby
attach_function :leptris_element_create, [:string], :element
attach_function :leptris_text_node_create, [:string], :element
attach_function :leptris_comment_node_create, [:string], :element
attach_function :leptris_cdata_node_create, [:string], :element
attach_function :leptris_pi_node_create, [:string, :string], :element
```

### Text / Comment / CDATA / PI access
```ruby
attach_function :leptris_text_node_get_content, [:node_ref], :string
attach_function :leptris_comment_node_get_content, [:node_ref], :string
attach_function :leptris_cdata_node_get_content, [:node_ref], :string
attach_function :leptris_pi_node_get_target, [:node_ref], :string
attach_function :leptris_pi_node_get_data, [:node_ref], :string
```

### XPath
```ruby
attach_function :leptris_xpath_eval,
  [:document, :element, :string], :xpath_result
attach_function :leptris_xpath_eval_with_vars,
  [:document, :string, :pointer], :xpath_result
attach_function :leptris_xpath_result_type, [:xpath_result], :int
attach_function :leptris_xpath_result_count, [:xpath_result], :size_t
attach_function :leptris_xpath_result_get, [:xpath_result, :size_t], :element
attach_function :leptris_xpath_result_boolean, [:xpath_result], :int
attach_function :leptris_xpath_result_number, [:xpath_result], :double
attach_function :leptris_xpath_result_string, [:xpath_result], :pointer
attach_function :leptris_xpath_result_free, [:xpath_result], :void
```

### XPath variables
```ruby
attach_function :leptris_xpath_variable_set_new, [], :pointer
attach_function :leptris_xpath_variable_set_free, [:pointer], :void
attach_function :leptris_xpath_variable_set_boolean, [:pointer, :string, :int], :int
attach_function :leptris_xpath_variable_set_number, [:pointer, :string, :double], :int
attach_function :leptris_xpath_variable_set_string, [:pointer, :string, :string], :int
```

### SAX
```ruby
# LeptrisSAXHandler is a struct of function pointers. Use FFI::Struct.
class SAXHandler < ::FFI::Struct
  layout \
    :start_document,    :pointer,
    :end_document,      :pointer,
    :start_element,     :pointer,
    :end_element,       :pointer,
    :characters,        :pointer,
    :comment,           :pointer,
    :cdata,             :pointer,
    :processing_instruction, :pointer,
    :start_prefix_mapping,   :pointer,
    :end_prefix_mapping,     :pointer,
    :error,             :pointer
end

attach_function :leptris_sax_parse,
  [:string, :size_t, SAXHandler.by_pointer, :pointer], :int
attach_function :leptris_sax_parser_create,
  [SAXHandler.by_pointer, :pointer], :sax_parser
attach_function :leptris_sax_parser_feed,
  [:sax_parser, :string, :size_t, :int], :int
attach_function :leptris_sax_parser_free, [:sax_parser], :void
attach_function :leptris_sax_parser_set_streaming,
  [:sax_parser, :int], :int
```

### Serialization
```ruby
# LeptrisSerializeOptions struct
class SerializeOptions < ::FFI::Struct
  layout \
    :indent,          :int,
    :xml_declaration, :int,
    :no_empty_tags,   :int,
    :preserve_whitespace, :int
end

attach_function :leptris_serialize_document,
  [:document, :pointer], :pointer
attach_function :leptris_c14n_canonicalize,
  [:document, :int, :int], :pointer
```

### Memory
```ruby
attach_function :leptris_free_string, [:pointer], :void
```

## Status codes

```ruby
LEPTRIS_OK              = 0
LEPTRIS_ERROR_MEMORY    = -1
LEPTRIS_ERROR_PARSE     = -2
LEPTRIS_ERROR_XPATH     = -3
LEPTRIS_ERROR_NULL_ARG  = -4
LEPTRIS_ERROR_INVALID_ARG = -5
LEPTRIS_ERROR_NOT_FOUND = -6
LEPTRIS_ERROR_IO        = -7
```

## Node type constants

```ruby
NODE_ELEMENT  = 0
NODE_ATTRIBUTE = 1
NODE_TEXT     = 2
NODE_COMMENT  = 3
NODE_CDATA    = 4
NODE_PI       = 5
NODE_DOCTYPE  = 6
```

## XPath result type constants

```ruby
XPATH_NODESET = 0
XPATH_BOOLEAN = 1
XPATH_NUMBER  = 2
XPATH_STRING  = 3
```

## Notes

- Use `Blocking: true` for SAX callbacks (FFI::Function).
- Use `AutoPointer` for document and xpath_result to get automatic
  cleanup. But ALSO provide explicit `#free` methods since GC timing
  is non-deterministic.
- The `leptris_element_*` functions that return `:string` return
  document-owned strings (valid until `leptris_document_free`).
  Ruby copies them automatically on FFI return — safe.
- Functions that return `:pointer` for strings (like
  `leptris_xpath_result_string`, `leptris_serialize_document`) return
  heap-owned strings that the caller must free via `leptris_free_string`.
