# frozen_string_literal: true

require "ffi"

# Compiled XQuery 1.0 query (libleptris 1.9.64+): parse once,
# evaluate many times against any document. The engine layer
# orchestrates the XPath engine — the prolog (declare variable /
# namespace / function local:*) binds into the evaluation context,
# FLWOR clauses run as a tuple stream, and results reuse the XPath
# result handle.
#
#     query = Leptris::XML::XQuery.parse(<<~XQ)
#       for $i in //item
#       where $i/@qty > 3
#       order by $i/@qty descending
#       return <big>{$i/name/text()}</big>
#     XQ
#     query.eval(doc)   # => Leptris::XML::NodeSet
#
class Leptris::XML::XQuery
  class Handle < ::FFI::AutoPointer
    def self.release(ptr)
      Leptris::XML::FFI.leptris_xquery_free(ptr)
    end
  end

  def self.parse(query)
    query = query.to_s
    raw = Leptris::XML::FFI.leptris_xquery_parse(query, query.bytesize)
    if raw.null?
      raise Leptris::XML::XPathError,
        "query parse failed: #{Leptris::XML::FFI.leptris_last_error}"
    end
    new(query, Handle.new(raw))
  end

  attr_reader :query

  def initialize(query, handle)
    @query = query
    @handle = handle
  end

  # Evaluates against +doc_or_element+. Plain-expression bodies keep
  # their XPath result type (NodeSet / true/false / Float / String);
  # FLWOR results arrive as the sequence channel — read them through
  # an aggregate until the engine materializes readable sequence
  # items (same caveat as the XPath for-return subset).
  def eval(doc_or_element)
    case doc_or_element
    when Leptris::XML::Document
      document = doc_or_element
      context = nil
    when Leptris::XML::Element
      document = doc_or_element.document
      context = doc_or_element.c_ptr
    else
      raise ArgumentError,
        "expected a Leptris::XML::Document or Element, got #{doc_or_element.class}"
    end
    result_ptr = Leptris::XML::FFI.leptris_xquery_eval(
      @handle, document.c_ptr, context)
    if result_ptr.null?
      raise Leptris::XML::XPathError,
        Leptris::XML::FFI.leptris_last_error.to_s
    end
    Leptris::XML::Searchable.wrap_xpath_result(document, result_ptr)
  end
end
