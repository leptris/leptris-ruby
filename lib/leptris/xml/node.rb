# frozen_string_literal: true

class Leptris::XML::Node
  attr_reader :c_ptr, :document

  def initialize(c_ptr, document, parent: nil)
    @c_ptr = c_ptr
    @document = document
    @parent = parent
  end

  def self.wrap(c_ptr, document, parent: nil)
    # Per-document weak-ref cache. Returns the existing wrapper when the
    # same c_ptr is wrapped twice (common in children/sibling walks,
    # repeated xpath queries, traverse-then-access patterns). The cache
    # dies with the document so no stale entries.
    if document && (cached = document.wrapper_cache[c_ptr.address])
      return cached
    end

    node =
      case Leptris::XML::FFI.leptris_node_get_type(c_ptr)
      when Leptris::XML::FFI::NODE_ELEMENT
        Leptris::XML::Element.new(c_ptr, document, parent: parent)
      when Leptris::XML::FFI::NODE_TEXT
        Leptris::XML::Text.new(c_ptr, document, parent: parent)
      when Leptris::XML::FFI::NODE_COMMENT
        Leptris::XML::Comment.new(c_ptr, document, parent: parent)
      when Leptris::XML::FFI::NODE_CDATA
        Leptris::XML::CDATA.new(c_ptr, document, parent: parent)
      when Leptris::XML::FFI::NODE_PI
        Leptris::XML::ProcessingInstruction.new(c_ptr, document, parent: parent)
      else
        new(c_ptr, document, parent: parent)
      end

    document.wrapper_cache[c_ptr.address] = node if document
    node
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
    Leptris::XML::FFI.leptris_node_get_type(@c_ptr)
  end
  alias_method :node_type, :type

  def element?;  type == Leptris::XML::FFI::NODE_ELEMENT;  end
  def text?;     type == Leptris::XML::FFI::NODE_TEXT;     end
  def comment?;  type == Leptris::XML::FFI::NODE_COMMENT;  end
  def cdata?;    type == Leptris::XML::FFI::NODE_CDATA;    end
  def processing_instruction?
    type == Leptris::XML::FFI::NODE_PI
  end
  alias_method :pi?, :processing_instruction?

  def parent
    return @parent if @parent
    ptr = Leptris::XML::FFI.leptris_node_parent(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::Element.new(ptr, @document)
  end

  def line
    Leptris::XML::FFI.leptris_node_line(@c_ptr)
  end

  def <=>(other)
    return nil unless other.is_a?(Leptris::XML::Node)
    return nil unless @document == other.document
    Leptris::XML::FFI.leptris_node_compare(@c_ptr, other.c_ptr)
  end

  def child
    ptr = Leptris::XML::FFI.leptris_node_first_child(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::Node.wrap(ptr, @document, parent: as_element_or_self)
  end

  def children
    nodes = []
    ptr = Leptris::XML::FFI.leptris_node_first_child(@c_ptr)
    until ptr.nil? || ptr.null?
      nodes << Leptris::XML::Node.wrap(ptr, @document, parent: as_element_or_self)
      ptr = Leptris::XML::FFI.leptris_node_next_sibling(ptr)
    end
    Leptris::XML::NodeSet.new(@document, nodes)
  end

  def next_sibling
    ptr = Leptris::XML::FFI.leptris_node_next_sibling(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::Node.wrap(ptr, @document, parent: @parent)
  end
  alias_method :next, :next_sibling

  def previous_sibling
    ptr = Leptris::XML::FFI.leptris_node_previous_sibling(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::Node.wrap(ptr, @document, parent: @parent)
  end
  alias_method :previous, :previous_sibling

  def first_element_child
    ptr = Leptris::XML::FFI.leptris_node_first_child(@c_ptr)
    until ptr.nil? || ptr.null?
      node = Leptris::XML::Node.wrap(ptr, @document, parent: as_element_or_self)
      return node if node.element?
      ptr = Leptris::XML::FFI.leptris_node_next_sibling(ptr)
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
    status = Leptris::XML::FFI.leptris_node_unlink(@c_ptr)
    raise Leptris::XML::Error,
      Leptris::XML::FFI.leptris_status_string(status) unless status == Leptris::XML::FFI::LEPTRIS_OK
    @parent = nil
    self
  end
  alias_method :remove, :unlink

  # Walks the subtree in post-order DFS (matches Nokogiri's semantics).
  #
  # Specialized hot path: skips the intermediate NodeSet allocation that
  # Element#children would create, walking via raw FFI calls and wrapping
  # nodes directly. Saves one Array + one NodeSet allocation per parent
  # node. For a tree of N nodes that's ~N fewer allocations on a full
  # traversal.
  #
  # Still pays ~2 FFI calls per visited node (first_child + next_sibling).
  # Beating Nokogiri on this benchmark needs C-side traverse with a
  # callback (libleptris #273); the per-node FFI cost is the floor.
  def traverse
    return enum_for(:traverse) unless block_given?
    callback = ::FFI::Function.new(:int, [:pointer, :pointer], blocking: true) do |node_ptr, _|
      yield Leptris::XML::Node.wrap(node_ptr, @document)
      0
    end
    Leptris::XML::FFI.leptris_node_traverse(
      @c_ptr, Leptris::XML::FFI::TRAVERSE_POST_ORDER, callback, nil)
  end

  def path
    str_ptr = Leptris::XML::FFI.leptris_node_get_xpath(@c_ptr)
    return nil if str_ptr.null?
    str_ptr.read_string.tap { Leptris::XML::FFI.leptris_free_string(str_ptr) }
  end

  def css_path
    return nil if path.nil?
    path.split("/").filter_map do |part|
      next nil if part.empty?
      part.gsub(/\[(\d+)\]/, ':nth-of-type(\1)')
    end.join(" > ")
  end

  def dup
    elem_ptr = Leptris::XML::FFI.leptris_node_as_element(@c_ptr)
    raise Leptris::XML::Error, "dup is only supported for element nodes" if elem_ptr.null?
    copy_ptr = Leptris::XML::FFI.leptris_element_copy(elem_ptr, @document.c_ptr)
    raise Leptris::XML::Error, "leptris_element_copy failed" if copy_ptr.null?
    Leptris::XML::Element.new(copy_ptr, @document)
  end
  alias_method :clone, :dup

  def ==(other)
    return false unless other.is_a?(Leptris::XML::Node)
    @c_ptr == other.c_ptr
  end

  def inspect
    "#<#{self.class.name} ptr=#{c_ptr}>"
  end

  protected

  def as_element_or_self
    is_a?(Leptris::XML::Element) ? self : nil
  end

  private

  # Walks the subtree in post-order DFS (matches Nokogiri's semantics).
  #
  # Specialized hot path for #traverse: skips the intermediate NodeSet
  # allocation that Element#children would create, walking via raw FFI
  # calls and wrapping nodes directly. Saves one Array + one NodeSet
  # allocation per parent node.
  #
  include Leptris::XML::Searchable
end
