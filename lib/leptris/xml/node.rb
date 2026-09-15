# frozen_string_literal: true

class Leptris::XML::Node
  attr_reader :c_ptr

  # Iterparse-yielded elements are owned by an IterationScope (the
  # internal lifetime/memoization authority) — the public #document
  # answers nil for them, per the documented contract.
  def document
    scope_owned? ? nil : @document
  end

  def initialize(c_ptr, document, parent: nil, node_type: nil)
    @c_ptr = c_ptr
    @document = document
    @parent = parent
    # Structural-memo stamp (TODO.perf/13): a constructor-seeded
    # @parent is true AS OF the document's current version; any
    # mutation advances the version and forces re-derivation. A
    # NIL constructor parent means UNKNOWN, not "no parent" — the
    # engine may attach during creation (create_child), so an
    # unstamped memo must derive rather than trust nil.
    @parent_version = parent ? document&.version : nil
    # Computed once: structural stamps apply to document-owned
    # nodes only (scope-owned iterparse elements move without
    # their scope's version advancing — see #parent). An ivar
    # keeps the memo-hit path free of method dispatch.
    @structure_memoizable =
      !document.nil? && !document.is_a?(Leptris::XML::IterationScope)
    # wrap() already calls leptris_node_get_type for dispatch; reusing
    # the result makes every predicate and #type call FFI-free.
    @node_type = node_type
  end

  # True when this node's owning context is an IterationScope
  # (iterparse-yielded) rather than a Document.
  def scope_owned?
    @document.is_a?(Leptris::XML::IterationScope)
  end
  private :scope_owned?

  # node_type: callers holding a batch-fetched kind (the XPath
  # result-set batch fills out_kinds) pass it so the wrap skips the
  # get_type dispatch; nil (the default) dispatches as before.
  # Factory variant: the pointer was JUST created by the engine,
  # so the cache lookup is a guaranteed miss — skip straight to
  # construction and store (identity still survives attach).
  def self.wrap_fresh(c_ptr, document, node_type)
    node = construct(c_ptr, document, nil, node_type, nil)
    if document
      cache = document.wrapper_cache
      cache[c_ptr.address] = node
    end
    node
  end

  def self.wrap(c_ptr, document, parent: nil, node_type: nil, result_value: nil)
    # Per-document weak-ref cache. Returns the existing wrapper when the
    # same c_ptr is wrapped twice (common in children/sibling walks,
    # repeated xpath queries, traverse-then-access patterns). The cache
    # dies with the document so no stale entries. The miss path
    # resolves the cache and address once — a cold walk wraps every
    # node exactly once and pays both only on the store.
    if document
      cache = document.wrapper_cache
      address = c_ptr.address
      if (cached = cache[address])
        # The shared cache also holds NativeNodes (opt-in layer).
        # Only return a hit when it is a binding Node subclass —
        # otherwise fall through and construct the binding wrapper
        # (both views of the same C node can coexist; the native
        # entry stays under its own key-path via NativeNode.from).
        return cached if cached.is_a?(Leptris::XML::Node)
      end
    end

    node_type ||= Leptris::XML::FFI.leptris_node_get_type(c_ptr)
    node = construct(c_ptr, document, parent, node_type, result_value)

    cache[address] = node if document
    node
  end

  # The single type-dispatch construction authority shared by wrap
  # (cache-checked) and wrap_fresh (factory path).
  def self.construct(c_ptr, document, parent, node_type, result_value)
    case node_type
    when Leptris::XML::FFI::NODE_ELEMENT
      Leptris::XML::Element.new(c_ptr, document, parent: parent, node_type: node_type)
    when Leptris::XML::FFI::NODE_TEXT
      Leptris::XML::Text.new(c_ptr, document, parent: parent, node_type: node_type)
    when Leptris::XML::FFI::NODE_SYNTHETIC_TEXT
      # Sequence/map/array items: value captured by the NodeSet at
      # materialization (only the result handle can read them).
      Leptris::XML::ResultText.new(
        c_ptr, document, result_value, parent: parent, node_type: node_type)
    when Leptris::XML::FFI::NODE_ATTRIBUTE
      # ruby#153: synthetic attribute result nodes carry their
      # name/value in the result handle — the NodeSet captures
      # them at materialization (result_value is a {name:, value:}
      # hash; the single-node seam captures the same way).
      rv = result_value || {}
      Leptris::XML::ResultAttr.new(
        c_ptr, document, rv[:name], rv[:value],
        parent: parent, node_type: node_type)
    when Leptris::XML::FFI::NODE_COMMENT
      Leptris::XML::Comment.new(c_ptr, document, parent: parent, node_type: node_type)
    when Leptris::XML::FFI::NODE_CDATA
      Leptris::XML::CDATA.new(c_ptr, document, parent: parent, node_type: node_type)
    when Leptris::XML::FFI::NODE_PI
      Leptris::XML::ProcessingInstruction.new(c_ptr, document, parent: parent, node_type: node_type)
    else
      new(c_ptr, document, parent: parent, node_type: node_type)
    end
  end
  private_class_method :construct

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

  # The ext bulk path applies to document-owned trees only:
  # scope-owned (iterparse) elements ride the IterationScope seam.
  def native_fast_children?
    defined?(Leptris::XML::NATIVE_FAST) &&
      !@document.is_a?(Leptris::XML::IterationScope)
  end

  # Content-defined 64-bit Merkle digest of this subtree
  # (libleptris 1.9.99, #869): element name/prefix/resolved
  # namespace URI, attributes sorted and first-wins-deduplicated,
  # children hashed in document order — no addresses participate,
  # so equal trees hash equal across processes. Equality implies
  # subtree equivalence; inequality implies nothing (descend).
  # +drop_ws+ skips whitespace-only text nodes.
  def digest(drop_ws: false)
    ensure_alive!
    Leptris::XML::FFI.leptris_node_digest(
      @c_ptr, drop_ws ? 1 : 0)
  end
  def text?;     type == Leptris::XML::FFI::NODE_TEXT;     end
  def comment?;  type == Leptris::XML::FFI::NODE_COMMENT;  end
  def cdata?;    type == Leptris::XML::FFI::NODE_CDATA;    end
  def processing_instruction?
    type == Leptris::XML::FFI::NODE_PI
  end
  alias_method :pi?, :processing_instruction?

  # Version-stamped structural memo (TODO.perf/13): derive once,
  # re-derive after any mutation that advances the owning
  # document's version. Fixes the stale seeded @parent after a
  # move (FFI children walks seed it; the move never cleared it).
  # Scope-owned (iterparse) elements never memoize: a scope element
  # adopted into a document moves without its scope's version
  # advancing, so a stamp would lie.
  def parent
    if @structure_memoizable && @parent_version == @document.version
      return @parent
    end
    ensure_alive!
    ptr = Leptris::XML::FFI.leptris_node_parent(@c_ptr)
    result = ptr.null? ? nil : Leptris::XML::Node.wrap(ptr, @document)
    if @document
      @parent = result
      @parent_version = @document.version
    end
    result
  end

  # Derive the parent WITHOUT stamping the structural memo. The
  # adoption lift reads the child's source scope BETWEEN the
  # mutation gate's version bump and the engine move — a stamped
  # #parent there would record post-bump versions carrying
  # pre-move truth. Ancestor walks that run inside mutations use
  # this; #namespaces itself is memoized, so stable trees pay the
  # unstamped derivation at most once per version.
  def unstamped_parent
    ensure_alive!
    ptr = Leptris::XML::FFI.leptris_node_parent(@c_ptr)
    ptr.null? ? nil : Leptris::XML::Node.wrap(ptr, @document)
  end

  # Mutation sites move nodes ACROSS documents: the moved node's
  # stamps reference the source document's version, which the move
  # does not advance. Clear them and advance the source version
  # (its other nodes hold parent/sibling stamps the move invalidates).
  def invalidate_structural_stamps!
    @parent_version = nil
    @next_sibling_version = nil
    @previous_sibling_version = nil
  end

  # Mutation-site helper: when +node+ moves into +target_document+
  # from a different one, the move invalidates the node's own
  # structural stamps (stamped against the SOURCE version) and the
  # source document's sibling/parent stamps. Scope-owned nodes
  # answer nil from #document and never memoize — nothing to do.
  def self.invalidate_cross_document!(node, target_document)
    source = node.document
    return if source.nil? || source.equal?(target_document)
    node.invalidate_structural_stamps!
    source.advance_version
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

  # Byte offset of the node's markup in its parse source (the '<'
  # of the tag; libleptris 1.9.162, #1039 — the position descriptor
  # CALLBACK rows echo). 0 when unknown: mutation-created nodes, or
  # documents >= 2 GiB.
  def byte_offset
    ensure_alive!
    Leptris::XML::FFI.leptris_node_byte_offset(@c_ptr)
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
    # construction is paid once. The kinds ride the batch
    # (leptris_node_children_ex), so no per-child get_type.
    return @children if memo_hit?(@children_version)
    ensure_alive!
    if native_fast_children?
      # TODO.perf/01 tail: one C pass constructs every binding
      # wrapper (class dispatch + ivars + identity cache) — the
      # per-child Ruby wrap frames disappear.
      nodes = Leptris::XML::Native.bulk_children(@document, @c_ptr.address)
      result = Leptris::XML::NodeSet.new(@document, nodes)
      if @document
        @children = result
        @children_version = @document.version
      end
      return result
    end
    parent = as_element_or_self
    pointers, kinds = Leptris::XML::FFI.fetch_children(@c_ptr)
    nodes = Array.new(pointers.size) do |i|
      Leptris::XML::Node.wrap(pointers[i], @document,
                              parent: parent, node_type: kinds[i])
    end
    result = Leptris::XML::NodeSet.new(@document, nodes)
    if @document
      @children = result
      @children_version = @document.version
    end
    result
  end

  def next_sibling
    if @structure_memoizable && @next_sibling_version == @document.version
      return @next_sibling
    end
    ensure_alive!
    ptr = Leptris::XML::FFI.leptris_node_next_sibling(@c_ptr)
    result = ptr.null? ? nil : Leptris::XML::Node.wrap(ptr, @document, parent: @parent)
    if @document
      @next_sibling = result
      @next_sibling_version = @document.version
    end
    result
  end
  alias_method :next, :next_sibling

  def previous_sibling
    if @structure_memoizable && @previous_sibling_version == @document.version
      return @previous_sibling
    end
    ensure_alive!
    ptr = Leptris::XML::FFI.leptris_node_previous_sibling(@c_ptr)
    result = ptr.null? ? nil : Leptris::XML::Node.wrap(ptr, @document, parent: @parent)
    if @document
      @previous_sibling = result
      @previous_sibling_version = @document.version
    end
    result
  end
  alias_method :previous, :previous_sibling

  def first_element_child
    return @first_element_child if memo_hit?(@first_element_child_version)
    ensure_alive!
    # Raw pointer scan: non-element siblings are typed with one C
    # call each — never wrapped, never cached — and the found
    # element carries the ELEMENT hint into the wrap.
    ptr = Leptris::XML::FFI.leptris_node_first_child(@c_ptr)
    result = nil
    until ptr.nil? || ptr.null?
      if Leptris::XML::FFI.leptris_node_get_type(ptr) ==
          Leptris::XML::FFI::NODE_ELEMENT
        result = Leptris::XML::Node.wrap(
          ptr, @document, parent: as_element_or_self,
          node_type: Leptris::XML::FFI::NODE_ELEMENT)
        break
      end
      ptr = Leptris::XML::FFI.leptris_node_next_sibling(ptr)
    end
    if @document
      @first_element_child = result
      @first_element_child_version = @document.version
    end
    result
  end

  def last_element_child
    # Element receivers: the element-only batch fetches pointers
    # without wrapping any text child; only the last is wrapped.
    if is_a?(Leptris::XML::Element)
      kids = Leptris::XML::FFI.fetch_element_children(@c_ptr)
      return nil if kids.empty?
      return Leptris::XML::Node.wrap(
        kids.last, @document, parent: self,
        node_type: Leptris::XML::FFI::NODE_ELEMENT)
    end
    children.reverse_each.find(&:element?)
  end

  def element_children
    return @element_children if memo_hit?(@element_children_version)
    ensure_alive!
    # Element receivers ride the element-only batch: text/comment
    # children are never wrapped (nor their get_type paid — the
    # ELEMENT hint rides along). Other nodes keep the filter.
    result =
      if native_fast_children?
        Leptris::XML::Native.bulk_element_children(@document, @c_ptr.address)
      elsif is_a?(Leptris::XML::Element)
        parent = as_element_or_self
        Leptris::XML::FFI.fetch_element_children(@c_ptr).map do |ptr|
          Leptris::XML::Node.wrap(ptr, @document, parent: parent,
                                  node_type: Leptris::XML::FFI::NODE_ELEMENT)
        end
      else
        children.select(&:element?)
      end
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

  # Visits the subtree with ONE C call (leptris_node_visit,
  # libleptris 1.9.20 — upstream #645a): elements yield twice —
  # (node, true, depth) before their children, (node, false, depth)
  # after the subtree completes — every other kind once with
  # entering=true; depth counts element levels from the receiver.
  # No NodeSet, pointer array, or children memo per level: the
  # leanest full-subtree iteration the binding offers (a document
  # receiver walks the document child chain). The walk is read-only
  # — mutate only between visits.
  #
  #     root.visit { |node, entering, depth| ... }
  def visit(&block)
    return enum_for(:visit) unless block
    ensure_alive!
    document = @document
    visitor = ::FFI::Function.new(
      :void, [:pointer, :pointer, :int, :int], blocking: true) do |_, node_ptr, entering, depth|
      block.call(
        Leptris::XML::Node.wrap(node_ptr, document),
        entering == 1, depth)
    end
    Leptris::XML::FFI.leptris_node_visit(@c_ptr, visitor, nil)
    self
  end

  # Walks the subtree in post-order DFS (matches Nokogiri's
  # semantics): the receiver, its descendants, nothing else.
  #
  # One FFI call dispatches the whole walk; the C engine invokes the
  # callback once per visited node (the only per-node cost is the
  # C-to-Ruby callback dispatch, not FFI round-trips).
  #
  # Subtree-bounded by abort-at-self (leptris-ruby#89): the C
  # walker was never bounded — after visiting the receiver it
  # pushes the receiver's NEXT SIBLING and continues to the end of
  # the document chain. In post-order the receiver is the LAST
  # node of its own subtree, so returning non-zero at self stops
  # the walk exactly at the boundary (the C loop honors a non-zero
  # callback return). The self comparison is by address; the
  # receiver's handle is stable for the walk's duration.
  #
  # Exceptions raised by the block are re-raised after the walk
  # (leptris-ruby#90): a rescue inside the callback stashes the
  # exception and returns non-zero, aborting the C walk — without
  # it the FFI dispatch silently swallowed the exception and the
  # walk continued with partially processed data.
  def traverse
    return enum_for(:traverse) unless block_given?
    ensure_alive!
    error = nil
    self_address = @c_ptr.address
    callback = ::FFI::Function.new(:int, [:pointer, :pointer], blocking: true) do |node_ptr, _|
      begin
        yield Leptris::XML::Node.wrap(node_ptr, @document)
        node_ptr.address == self_address ? 1 : 0
      rescue Exception => e # rubocop:disable Lint/RescueException
        error = e
        1
      end
    end
    Leptris::XML::FFI.leptris_node_traverse(
      @c_ptr, Leptris::XML::FFI::TRAVERSE_POST_ORDER, callback, nil)
    raise error if error
    self
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

  # Deep copy in a NEW document via Document.copy_of (the single
  # copy seam — comment/PI children and namespaces both survive,
  # #696/#721/#812; the copier is pool-threaded, ~2.3x Nokogiri;
  # non-element kinds rebuild by value — #161).
  def dup
    ensure_alive!
    Leptris::XML::Document.copy_of(self)
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
