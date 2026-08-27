# frozen_string_literal: true

class Leptris::XML::Node
  attr_reader :c_ptr, :document

  def initialize(c_ptr, document, parent: nil, node_type: nil)
    @c_ptr = c_ptr
    @document = document
    @parent = parent
    # wrap() already calls leptris_node_get_type for dispatch; reusing
    # the result makes every predicate and #type call FFI-free.
    @node_type = node_type
  end

  def self.wrap(c_ptr, document, parent: nil)
    # Per-document weak-ref cache. Returns the existing wrapper when the
    # same c_ptr is wrapped twice (common in children/sibling walks,
    # repeated xpath queries, traverse-then-access patterns). The cache
    # dies with the document so no stale entries.
    if document && (cached = document.wrapper_cache[c_ptr.address])
      return cached
    end

    node_type = Leptris::XML::FFI.leptris_node_get_type(c_ptr)
    node =
      case node_type
      when Leptris::XML::FFI::NODE_ELEMENT
        Leptris::XML::Element.new(c_ptr, document, parent: parent, node_type: node_type)
      when Leptris::XML::FFI::NODE_TEXT
        Leptris::XML::Text.new(c_ptr, document, parent: parent, node_type: node_type)
      when Leptris::XML::FFI::NODE_COMMENT
        Leptris::XML::Comment.new(c_ptr, document, parent: parent, node_type: node_type)
      when Leptris::XML::FFI::NODE_CDATA
        Leptris::XML::CDATA.new(c_ptr, document, parent: parent, node_type: node_type)
      when Leptris::XML::FFI::NODE_PI
        Leptris::XML::ProcessingInstruction.new(c_ptr, document, parent: parent, node_type: node_type)
      else
        new(c_ptr, document, parent: parent, node_type: node_type)
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

  # Dispatching defs, not alias_method: an alias snapshots this base
  # #content (the raise), so subclass overrides would never be seen
  # through the alias. A plain method resolves #content per-call.
  def text
    content
  end

  def inner_text
    content
  end

  def type
    return @node_type if @node_type
    ensure_alive!
    @node_type = Leptris::XML::FFI.leptris_node_get_type(@c_ptr)
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
    ensure_alive!
    ptr = Leptris::XML::FFI.leptris_node_parent(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::Node.wrap(ptr, @document)
  end

  # Borrowed-handle lifetime: every c_ptr dereference is valid only
  # while the owning document lives. Parentless nodes (iterparse
  # yields) cannot validate and are skipped. The guard runs before
  # every uncached FFI dispatch, so it uses the cheapest sufficient
  # check: #free nils the document's c_ptr, and the GC-finalizer
  # path cannot fire while any handle (which strongly references
  # the document) exists. Document#freed? remains the accurate
  # public predicate.
  def ensure_alive!
    if @document && @document.c_ptr.nil?
      raise Leptris::XML::UseAfterFreeError,
        "owning document has been freed — handle used on #{inspect}"
    end
  end

  # Raises ReadOnlyError when the owning document was marked readonly,
  # UseAfterFreeError when it was freed. Every node-level mutation
  # passes through this gate, so it is where the document's mutation
  # version advances — the invalidation behind writable-document
  # memoization. Bumping before the C call is conservative: a failed
  # mutation merely discards memos.
  def ensure_writable!
    ensure_alive!
    if readonly_document?
      raise Leptris::XML::ReadOnlyError,
        "document is readonly — mutation attempted on #{inspect}"
    end
    @document.advance_version
    nil
  end

  # Readonly is one-way, so caching TRUE is sound: once observed,
  # the document is readonly forever. FALSE stays uncached (the
  # document may still flip). Saves the document round-trip on
  # per-read guards.
  def readonly_document?
    return true if instance_variable_defined?(:@readonly_document)
    return false unless @document&.readonly?
    @readonly_document = true
  end

  def line
    ensure_alive!
    Leptris::XML::FFI.leptris_node_line(@c_ptr)
  end

  def <=>(other)
    return nil unless other.is_a?(Leptris::XML::Node)
    return nil unless @document == other.document
    ensure_alive!
    Leptris::XML::FFI.leptris_node_compare(@c_ptr, other.c_ptr)
  end

  def child
    ensure_alive!
    ptr = Leptris::XML::FFI.leptris_node_first_child(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::Node.wrap(ptr, @document, parent: as_element_or_self)
  end

  def children
    # Immutable in readonly mode: the batch fetch plus wrapper
    # construction is paid once.
    return @children if memo_hit?(@children_version)
    ensure_alive!
    parent = as_element_or_self
    nodes = Leptris::XML::FFI.fetch_children(@c_ptr).map do |ptr|
      Leptris::XML::Node.wrap(ptr, @document, parent: parent)
    end
    result = Leptris::XML::NodeSet.new(@document, nodes)
    if @document
      @children = result
      @children_version = @document.version
    end
    result
  end

  def next_sibling
    ensure_alive!
    ptr = Leptris::XML::FFI.leptris_node_next_sibling(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::Node.wrap(ptr, @document, parent: @parent)
  end
  alias_method :next, :next_sibling

  def previous_sibling
    ensure_alive!
    ptr = Leptris::XML::FFI.leptris_node_previous_sibling(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::Node.wrap(ptr, @document, parent: @parent)
  end
  alias_method :previous, :previous_sibling

  def first_element_child
    ensure_alive!
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
    return @element_children if memo_hit?(@element_children_version)
    result = children.select(&:element?)
    if @document
      @element_children = result
      @element_children_version = @document.version
    end
    result
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
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_node_unlink(@c_ptr))
    @parent = nil
    self
  end
  alias_method :remove, :unlink

  # Walks the subtree in post-order DFS (matches Nokogiri's semantics).
  #
  # One FFI call dispatches the whole walk; the C engine invokes the
  # callback once per visited node (the only per-node cost is the
  # C-to-Ruby callback dispatch, not FFI round-trips).
  def traverse
    return enum_for(:traverse) unless block_given?
    ensure_alive!
    callback = ::FFI::Function.new(:int, [:pointer, :pointer], blocking: true) do |node_ptr, _|
      yield Leptris::XML::Node.wrap(node_ptr, @document)
      0
    end
    Leptris::XML::FFI.leptris_node_traverse(
      @c_ptr, Leptris::XML::FFI::TRAVERSE_POST_ORDER, callback, nil)
  end

  def path
    return @path if memo_hit?(@path_version)
    ensure_alive!
    str_ptr = Leptris::XML::FFI.leptris_node_get_xpath(@c_ptr)
    result = str_ptr.null? ? nil : Leptris::XML::FFI.read_owned_string(str_ptr)
    if @document
      @path = result
      @path_version = @document.version
    end
    result
  end

  def css_path
    return @css_path if memo_hit?(@css_path_version)
    result =
      if path.nil?
        nil
      else
        path.split("/").filter_map do |part|
          next nil if part.empty?
          part.gsub(/\[(\d+)\]/, ':nth-of-type(\1)')
        end.join(" > ")
      end
    if @document
      @css_path = result
      @css_path_version = @document.version
    end
    result
  end

  def dup
    ensure_alive!
    elem_ptr = Leptris::XML::FFI.leptris_node_as_element(@c_ptr)
    raise Leptris::XML::Error, "dup is only supported for element nodes" if elem_ptr.null?
    copy_ptr = Leptris::XML::FFI.leptris_element_copy(elem_ptr, @document.c_ptr)
    raise Leptris::XML::Error, "leptris_element_copy failed" if copy_ptr.null?
    Leptris::XML::Node.wrap(copy_ptr, @document)
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

  # A memo is valid while the document's mutation version has not
  # advanced since that memo was stored. Each memoized field carries
  # its OWN stamp — a shared node-level stamp would let one field's
  # recompute resurrect another field's stale memo. Readonly
  # documents never advance the version, so their memos are forever
  # valid (ADR 0003 semantics); writable documents gain memos
  # between mutations.
  def memo_hit?(stamp)
    @document && stamp == @document.version
  end

  def as_element_or_self
    is_a?(Leptris::XML::Element) ? self : nil
  end

  include Leptris::XML::Searchable
end
