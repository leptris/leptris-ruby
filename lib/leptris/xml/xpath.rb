# frozen_string_literal: true

require "ffi"

# Compiled XPath expression: parse once, evaluate many times against
# any document (libleptris v1.6.0). The C handle is released by GC.
#
#     expr = Leptris::XML::XPath.compile("//item[@qty > 3]")
#     expr.eval(doc_a).length
#     expr.eval(doc_b, "p" => "urn:p").length
#
class Leptris::XML::XPath
  class CompiledHandle < ::FFI::AutoPointer
    def self.release(ptr)
      Leptris::XML::FFI.leptris_xpath_compiled_free(ptr)
    end
  end

  attr_reader :expression

  def self.compile(expression)
    raw = Leptris::XML::FFI.leptris_xpath_compile(expression.to_s)
    if raw.null?
      raise Leptris::XML::XPathError,
        "invalid expression: #{Leptris::XML::FFI.leptris_last_error}"
    end
    new(expression.to_s, CompiledHandle.new(raw))
  end

  def initialize(expression, handle)
    @expression = expression
    @handle = handle
  end

  # Evaluates against +doc_or_element+. An optional trailing hash of
  # namespace bindings ("prefix" => uri) routes the evaluation through
  # the namespace-bound path, matching Searchable#xpath semantics.
  def eval(doc_or_element, ns = nil)
    context = Leptris::XML::EvaluationContext.of(doc_or_element)
    document = context.document
    result_ptr =
      if ns && !ns.empty?
        Leptris::XML::FFI.with_ns_set(ns) do |set|
          Leptris::XML::FFI.leptris_xpath_compiled_eval_ns(
            @handle, document.c_ptr, context.context_node_ptr, set)
        end
      else
        Leptris::XML::FFI.leptris_xpath_compiled_eval(
          @handle, document.c_ptr, context.context_node_ptr)
      end
    if result_ptr.null?
      raise Leptris::XML::XPathError,
        Leptris::XML::FFI.leptris_last_error.to_s
    end
    Leptris::XML::Searchable.wrap_xpath_result(document, result_ptr)
  end
end
