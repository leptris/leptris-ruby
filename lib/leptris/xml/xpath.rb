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

  # +version+ (#183, mirroring leptris-py#105): nil compiles the
  # full-grammar expression (the default); :xpath10 / "1.0" pins
  # the strict XPath 1.0 surface. Validated at the boundary.
  def self.compile(expression, version: nil)
    raw = Leptris::XML::FFI.leptris_xpath_compile(expression.to_s)
    if raw.null?
      raise Leptris::XML::XPathError,
        "invalid expression: #{Leptris::XML::FFI.leptris_last_error}"
    end
    version_code =
      Leptris::XML::Searchable.xpath_version_code(version) if version
    new(expression.to_s, CompiledHandle.new(raw), version_code)
  end

  # Raw-pointer evaluation for Searchable's compiled cache
  # (TODO.perf/15): the same entry the string path uses, against
  # the compiled handle — no per-call parse/cache lookup.
  def eval_ptrs(doc_ptr, context_ptr)
    Leptris::XML::FFI.leptris_xpath_compiled_eval(
      @handle, doc_ptr, context_ptr)
  end

  def initialize(expression, handle, version_code = nil)
    @expression = expression
    @handle = handle
    @version_code = version_code
  end

  # Evaluates against +doc_or_element+. An optional trailing hash of
  # namespace bindings ("prefix" => uri) routes the evaluation through
  # the namespace-bound path, matching Searchable#xpath semantics.
  # A compiled version pin routes through the engine's versioned
  # entry instead of the compiled handle — there is no compiled
  # versioned lane yet (engine gap), so the strict-1.0 surface is
  # enforced per evaluation over the stored expression.
  def eval(doc_or_element, ns = nil)
    context = Leptris::XML::EvaluationContext.of(doc_or_element)
    document = context.document
    result_ptr =
      if @version_code
        raise ArgumentError,
          "version: cannot be combined with namespace bindings "           "(the versioned engine entry takes no ns set yet)" if ns && !ns.empty?
        Leptris::XML::FFI.leptris_xpath_eval_versioned(
          document.c_ptr, context.context_node_ptr,
          @expression, @version_code, nil)
      elsif ns && !ns.empty?
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
