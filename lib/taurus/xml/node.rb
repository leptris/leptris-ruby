# frozen_string_literal: true

class Taurus::XML::Node
  attr_reader :c_ptr, :document

  def initialize(c_ptr, document, parent: nil)
    @c_ptr = c_ptr
    @document = document
    @parent = parent
  end

  def self.wrap(c_ptr, document, parent: nil)
    case Taurus::XML::FFI.taurus_node_get_type(c_ptr)
    when Taurus::XML::FFI::NODE_ELEMENT
      Taurus::XML::Element.new(c_ptr, document, parent: parent)
    when Taurus::XML::FFI::NODE_TEXT
      Taurus::XML::Text.new(c_ptr, document, parent: parent)
    when Taurus::XML::FFI::NODE_COMMENT
      Taurus::XML::Comment.new(c_ptr, document, parent: parent)
    when Taurus::XML::FFI::NODE_CDATA
      Taurus::XML::CDATA.new(c_ptr, document, parent: parent)
    when Taurus::XML::FFI::NODE_PI
      Taurus::XML::ProcessingInstruction.new(c_ptr, document, parent: parent)
    else
      new(c_ptr, document, parent: parent)
    end
  end

  def name
    raise NotImplementedError, "#{self.class}#name not implemented"
  end

  def content
    raise NotImplementedError, "#{self.class}#content not implemented"
  end
  alias_method :text, :content
  alias_method :inner_text, :content

  def type
    Taurus::XML::FFI.taurus_node_get_type(@c_ptr)
  end
  alias_method :node_type, :type

  def element?;  type == Taurus::XML::FFI::NODE_ELEMENT;  end
  def text?;     type == Taurus::XML::FFI::NODE_TEXT;     end
  def comment?;  type == Taurus::XML::FFI::NODE_COMMENT;  end
  def cdata?;    type == Taurus::XML::FFI::NODE_CDATA;    end
  def processing_instruction?
    type == Taurus::XML::FFI::NODE_PI
  end
  alias_method :pi?, :processing_instruction?

  def parent
    return @parent if @parent
    ptr = Taurus::XML::FFI.taurus_node_parent(@c_ptr)
    return nil if ptr.null?
    Taurus::XML::Element.new(ptr, @document)
  end

  def line
    Taurus::XML::FFI.taurus_node_line(@c_ptr)
  end

  def <=>(other)
    return nil unless other.is_a?(Taurus::XML::Node)
    return nil unless @document == other.document
    Taurus::XML::FFI.taurus_node_compare(@c_ptr, other.c_ptr)
  end

  def child
    ptr = Taurus::XML::FFI.taurus_node_first_child(@c_ptr)
    return nil if ptr.null?
    Taurus::XML::Node.wrap(ptr, @document, parent: as_element_or_self)
  end

  def children
    nodes = []
    ptr = Taurus::XML::FFI.taurus_node_first_child(@c_ptr)
    until ptr.nil? || ptr.null?
      nodes << Taurus::XML::Node.wrap(ptr, @document, parent: as_element_or_self)
      ptr = Taurus::XML::FFI.taurus_node_next_sibling(ptr)
    end
    Taurus::XML::NodeSet.new(@document, nodes)
  end

  def next_sibling
    ptr = Taurus::XML::FFI.taurus_node_next_sibling(@c_ptr)
    return nil if ptr.null?
    Taurus::XML::Node.wrap(ptr, @document, parent: @parent)
  end
  alias_method :next, :next_sibling

  def previous_sibling
    ptr = Taurus::XML::FFI.taurus_node_previous_sibling(@c_ptr)
    return nil if ptr.null?
    Taurus::XML::Node.wrap(ptr, @document, parent: @parent)
  end
  alias_method :previous, :previous_sibling

  def first_element_child
    ptr = Taurus::XML::FFI.taurus_node_first_child(@c_ptr)
    until ptr.nil? || ptr.null?
      node = Taurus::XML::Node.wrap(ptr, @document, parent: as_element_or_self)
      return node if node.element?
      ptr = Taurus::XML::FFI.taurus_node_next_sibling(ptr)
    end
    nil
  end

  def last_element_child
    children.reverse_each.find(&:element?)
  end

  def element_children
    children.select(&:element?)
  end
  alias_method :elements, :element_children

  def next_element
    sibling = next_sibling
    sibling = sibling.next_sibling until sibling.nil? || sibling.element?
    sibling
  end

  def previous_element
    sibling = previous_sibling
    sibling = sibling.previous_sibling until sibling.nil? || sibling.element?
    sibling
  end

  def unlink
    status = Taurus::XML::FFI.taurus_node_unlink(@c_ptr)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    @parent = nil
    self
  end
  alias_method :remove, :unlink

  def traverse
    return enum_for(:traverse) unless block_given?
    children.each { |child| child.traverse { |n| yield n } }
    yield self
  end

  def ==(other)
    return false unless other.is_a?(Taurus::XML::Node)
    @c_ptr == other.c_ptr
  end

  def inspect
    "#<#{self.class.name} ptr=#{c_ptr}>"
  end

  protected

  def as_element_or_self
    is_a?(Taurus::XML::Element) ? self : nil
  end

  include Taurus::XML::Searchable
end
