# frozen_string_literal: true

require "ffi"

# Resolves an expression-face receiver into its evaluation context:
# the OWNING document (lifetime + memoization scope) and the
# context-node pointer (nil at document level). The single typed
# seam behind XPath#eval and XQuery#eval — one authority, one
# ArgumentError shape, as the expression faces multiply.
#
#     context = Leptris::XML::EvaluationContext.of(node)
#     context.document        # => Leptris::XML::Document
#     context.context_node_ptr # => FFI::Pointer or nil
#
class Leptris::XML::EvaluationContext
  def self.of(receiver)
    case receiver
    when Leptris::XML::Document then new(receiver, nil)
    when Leptris::XML::Element then new(receiver.document, receiver.c_ptr)
    else
      raise ArgumentError,
        "expected a Leptris::XML::Document or Element, got #{receiver.class}"
    end
  end

  def initialize(document, context_node_ptr)
    @document = document
    @context_node_ptr = context_node_ptr
  end

  attr_reader :document, :context_node_ptr
end
