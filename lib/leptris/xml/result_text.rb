# frozen_string_literal: true

# Text-kind item from an XPath/XQuery sequence result: the engine
# materializes sequence, map, and array items as synthetic text
# nodes (leptris/types.h's internal kind 8) whose value is readable
# only through the live result handle — the node-pointer accessors
# return nothing for them. The NodeSet therefore captures the string
# value at materialization time and hands it to this wrapper.
#
#     doc.xpath("for $w in //a return string($w/@v)").map(&:content)
#     # => ["1", "2"]
#
class Leptris::XML::ResultText < Leptris::XML::Node
  def initialize(c_ptr, document, value, parent: nil, node_type: nil)
    super(c_ptr, document, parent: parent, node_type: node_type)
    @value = value
  end

  def name
    "text"
  end

  # The captured string: safe to read even after the owning result
  # set has been collected (unlike pointer-backed reads).
  def content
    @value
  end

  def to_s
    @value
  end

  def text?
    true
  end
end
