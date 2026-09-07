# frozen_string_literal: true

# Attribute-kind item from an XPath result set (ruby#153): the
# engine exposes synthetic attribute nodes whose name and value are
# readable only through the live result handle — the NodeSet
# captures both at materialization time and hands them to this
# wrapper, so the faces stay usable after the result is freed.
#
#     doc.xpath("//item/@id").first.name  # => "id"
#     doc.xpath("//item/@id").first.value # => "1"
#
class Leptris::XML::ResultAttr < Leptris::XML::Node
  def initialize(c_ptr, document, name, value, parent: nil, node_type: nil)
    super(c_ptr, document, parent: parent, node_type: node_type)
    @attr_name = name
    @attr_value = value
  end

  def name
    @attr_name
  end

  # Nokogiri's Attr#value is the attribute's string value.
  def value
    @attr_value
  end

  def content
    @attr_value
  end

  def to_s
    @attr_value
  end

  def attribute?
    true
  end
end
