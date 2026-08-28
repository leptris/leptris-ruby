# frozen_string_literal: true

require "ffi"

class Leptris::XML::Document
  attr_reader :c_ptr

  # @api private
  # Internal flag container shared between the Document instance and its
  # GC finalizer. Using a one-element Array because Procs close over
  # variables by reference — mutating freed[0] is visible from both
  # the explicit `free` path and the finalizer. This eliminates the
  # double-free that FFI::AutoPointer's release proc caused when
  # `Document#free` was called explicitly and then GC ran.
  Freed = Struct.new(:state)  # state: :alive | :freed

  # Mutation version: advanced by every data mutation (via
  # Node#ensure_writable!, root=, add_pi). Node memos stamp the
  # version they were computed under and recompute after any bump —
  # the invalidation that makes WRITABLE-document memoization sound.
  # Readonly documents never advance it, so their memos are forever
  # valid (ADR 0003 semantics, unchanged).
  def version
    @version
  end

  # Called by the mutation gates (Node#ensure_writable!, root=,
  # add_pi) — every memo stamped with an older version discards.
  def advance_version
    @version += 1
  end

  def initialize(c_ptr = nil, freed = Freed.new(:alive))
    @c_ptr = c_ptr
    @freed = freed
    @readonly = false
    @version = 0
    # Per-document STRONG cache for Node wrappers, keyed on c_ptr
    # address. Every wrapper is created through Node.wrap, which is the
    # single construction path, so the same C node always yields the
    # same Ruby object. Cleared when the Document is freed — no stale
    # entries.
    #
    # Deliberately NOT ObjectSpace::WeakMap: a weak cache makes wrapper
    # identity a GC race. `doc.root.equal?(doc.root)` failed on the
    # Windows CI matrix (188 examples, the 4 identity specs) because
    # between the two calls the first wrapper was referenced only by
    # the weak map — any GC sweep evicted it and the second call built
    # a fresh object. A strong cache costs at most one wrapper per node
    # actually visited, held until the document dies.
    #
    # Allocated lazily: parse-heavy loops stop paying one Hash per
    # document for trees that are freed before any wrap.
  end

  def wrapper_cache
    @wrapper_cache ||= {}
  end

  def self.parse(xml_or_io, options: nil, readonly: false, recover: false)
    xml = xml_or_io.respond_to?(:read) ? xml_or_io.read : xml_or_io.to_s
    if xml.empty?
      raise Leptris::XML::ParseError, "empty input"
    end
    if options.nil?
      options = Leptris::XML::ParseOptions.new(recover: recover)
    elsif recover && !options.recover?
      options = options | Leptris::XML::ParseOptions.new(recover: true)
    elsif !options.is_a?(Leptris::XML::ParseOptions)
      raise ArgumentError, "options must be a Leptris::XML::ParseOptions"
    end
    # The status out-param is nullable; the thread-local last error
    # carries failure detail, and skipping the per-parse MemoryPointer
    # is measurable on small documents.
    raw =
      if options.struct_required?
        # Recover is a struct field, not a parse flag — the options
        # struct path (leptris_parse_string_ex) is the only carrier.
        options_struct = options.to_c_struct
        Leptris::XML::FFI.leptris_parse_string_ex(
          xml, xml.bytesize, options_struct.pointer, nil)
      elsif options.flags.zero?
        Leptris::XML::FFI.leptris_parse_string(xml, xml.bytesize, nil)
      else
        Leptris::XML::FFI.leptris_parse_string_flags(
          xml, xml.bytesize, options.flags, nil)
      end
    if raw.null?
      if options.recover?
        # Unreachable in practice: recover returns an empty document
        # rather than NULL; kept so a contract change fails loudly.
        raise Leptris::XML::Error,
          "leptris_parse_string_ex returned NULL under recover"
      end
      raise Leptris::XML::ParseError,
        "leptris_parse_string failed: " +
        Leptris::XML::FFI.leptris_last_error.to_s
    end
    wrap(raw).tap { |doc| doc.readonly! if readonly }
  end

  def self.parse_file(path, readonly: false)
    raw = Leptris::XML::FFI.leptris_parse_file(path, nil)
    if raw.null?
      raise Leptris::XML::ParseError,
        "leptris_parse_file failed: " +
        Leptris::XML::FFI.leptris_last_error.to_s
    end
    wrap(raw).tap { |doc| doc.readonly! if readonly }
  end

  # Create an empty document (no root element) backed by its own memory
  # pool. Elements for the tree are created against it via
  # #create_element and friends, then attached with #root=.
  def self.create
    raw = Leptris::XML::FFI.leptris_document_create
    raise Leptris::XML::Error,
      "leptris_document_create failed" if raw.null?
    wrap(raw)
  end

  # Convert a raw LeptrisDocument pointer into a Ruby Document with safe
  # GC lifetime management. The finalizer captures the raw address
  # integer (not the Document or Pointer object — those would prevent
  # GC) and shares a one-shot flag with the instance so explicit
  # `#free` and the GC finalizer can never both call
  # `leptris_document_free` on the same address.
  def self.wrap(raw_address)
    addr = raw_address.is_a?(::FFI::Pointer) ? raw_address.address : raw_address
    ptr = ::FFI::Pointer.new(addr)
    freed = Freed.new(:alive)
    doc = new(ptr, freed)
    ObjectSpace.define_finalizer(doc, finalizer(addr, freed))
    doc
  end

  def self.finalizer(address, freed)
    proc do
      next if freed.state == :freed
      freed.state = :freed
      Leptris::XML::FFI.leptris_document_free(::FFI::Pointer.new(address))
    end
  end
  private_class_method :finalizer

  def root
    raise Leptris::XML::UseAfterFreeError if @freed.state == :freed
    return nil if @c_ptr.nil?
    ptr = Leptris::XML::FFI.leptris_document_root(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  # The document node — navigation head over the whole tree chain
  # [prolog comments/PIs, root element, epilog comments/PIs] in
  # document order (libleptris 1.9.7, upstream #580: the libxml2
  # model; XPath /comment() and //processing-instruction() see the
  # document-level nodes). A stable, document-owned singleton —
  # Node.wrap's cache keeps the returned wrapper identical.
  def node
    raise Leptris::XML::UseAfterFreeError if @freed.state == :freed
    @node ||= Leptris::XML::Node.wrap(
      Leptris::XML::FFI.leptris_document_node(@c_ptr), self)
  end

  # The document's children, via the document node: prolog
  # comments/PIs, the root element, epilog comments/PIs, in
  # document order (Nokogiri-parity shape).
  #
  # On programmatically built documents the C document node's chain
  # misses a root attached via #root= until some other document
  # mutation refreshes it (leptris-ruby#91 — libleptris's
  # document_set_root does not register into the chain). The merge
  # below splices the attached root in by document order whenever
  # the chain lacks it, so parsed and built documents read the
  # same. Prolog/epilog placement uses node_compare against the
  # root.
  def children
    doc_node = node
    return Leptris::XML::NodeSet.new(self, []) if doc_node.nil?
    kids = doc_node.children.to_a
    root_ptr = Leptris::XML::FFI.leptris_document_root(@c_ptr)
    return kids if root_ptr.null?
    return kids if kids.any? { |child| child.c_ptr == root_ptr }
    root = Leptris::XML::Node.wrap(root_ptr, self)
    # A replaced root stays in the C chain until another document
    # mutation refreshes it — the chain's element slots other than
    # the current root are stale old roots. The new root inherits
    # the first stale slot's position (the prolog/epilog split
    # follows where the old root sat); with no stale element
    # (programmatically built documents) placement falls back to
    # document-order comparison.
    stale = kids.select do |child|
      child.element? && child.c_ptr != root_ptr
    end
    if stale.any?
      kept = kids.reject { |child| stale.include?(child) }
      slot = kids.index(stale.first)
      kept.insert(slot, root)
      Leptris::XML::NodeSet.new(self, kept)
    else
      prolog, epilog = kids.partition do |child|
        Leptris::XML::FFI.leptris_node_compare(child.c_ptr, root_ptr).negative?
      end
      Leptris::XML::NodeSet.new(self, prolog + [root] + epilog)
    end
  end

  # Attach +element+ as the document's root element. The element must
  # have been created against this document and must not already have
  # a parent. Any previous root is left detached (still owned by the
  # document's pool until #free).
  def root=(element)
    raise Leptris::XML::UseAfterFreeError if @freed.state == :freed
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_document_set_root(@c_ptr, element.c_ptr))
    @version += 1
    element
  end

  def create_element(name)
    ptr = Leptris::XML::FFI.leptris_element_create(@c_ptr, name)
    raise Leptris::XML::Error, "leptris_element_create failed" if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  def create_text_node(content)
    ptr = Leptris::XML::FFI.leptris_text_node_create(@c_ptr, content.to_s)
    raise Leptris::XML::Error, "leptris_text_node_create failed" if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  def create_comment(content)
    ptr = Leptris::XML::FFI.leptris_comment_node_create(@c_ptr, content.to_s)
    raise Leptris::XML::Error, "leptris_comment_node_create failed" if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  def create_cdata(content)
    ptr = Leptris::XML::FFI.leptris_cdata_node_create(@c_ptr, content.to_s)
    raise Leptris::XML::Error, "leptris_cdata_node_create failed" if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  def create_processing_instruction(target, data = "")
    ptr = Leptris::XML::FFI.leptris_pi_node_create(@c_ptr, target.to_s, data.to_s)
    raise Leptris::XML::Error, "leptris_pi_node_create failed" if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  def fragment(markup)
    Leptris::XML::DocumentFragment.parse(markup, self)
  end

  def dup
    raw = Leptris::XML::FFI.leptris_document_copy(@c_ptr)
    raise Leptris::XML::Error, "leptris_document_copy failed" if raw.null?
    self.class.wrap(raw)
  end
  alias_method :clone, :dup

  def doctype
    ptr = Leptris::XML::FFI.leptris_document_internal_subset(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::DocType.new(ptr, self)
  end
  alias_method :internal_subset, :doctype

  # indent_text: true selects the display form (libleptris 1.9.9,
  # #129): text and mixed content indent too — the output is
  # display-oriented and not round-trip-guaranteed.
  def to_xml(indent: 0, no_decl: false, encoding: nil, indent_text: false)
    raise Leptris::XML::UseAfterFreeError if @freed.state == :freed
    return "" if @c_ptr.nil?
    if indent_text
      return Leptris::XML::Serialization.to_xml_display(
        @c_ptr, indent: indent, no_decl: no_decl, encoding: encoding)
    end
    Leptris::XML::Serialization.to_xml(
      Leptris::XML::FFI.method(:leptris_document_serialize_into), @c_ptr,
      indent: indent, no_decl: no_decl, encoding: encoding)
  end
  alias_method :to_s, :to_xml
  alias_method :serialize, :to_xml

  def save(path, **opts)
    opts_struct, _encoding_anchor = Leptris::XML::Serialization.build_options(
      indent: opts.fetch(:indent, 0),
      no_decl: opts.fetch(:no_decl, false),
      encoding: opts[:encoding])
    status = Leptris::XML::FFI.leptris_document_save_file(
      @c_ptr, path, opts_struct.pointer)
    Leptris::XML::FFI.check_status(status)
    self
  end

  def canonicalize(version = Leptris::XML::FFI::C14N_1_0,
                   inclusive_namespaces = nil,
                   with_comments: false,
                   exclusive: false,
                   mode: nil)
    raise Leptris::XML::UseAfterFreeError if @freed.state == :freed
    return "" if @c_ptr.nil?
    resolved_mode = mode || (exclusive ? Leptris::XML::FFI::C14N_MODE_EXCLUSIVE
                                       : Leptris::XML::FFI::C14N_MODE_CANONICAL)
    Leptris::XML::Serialization.canonicalize(
      Leptris::XML::FFI.method(:leptris_c14n_canonicalize_ex), @c_ptr,
      version: version, mode: resolved_mode,
      inclusive_namespaces: inclusive_namespaces,
      with_comments: with_comments)
  end
  alias_method :c14n, :canonicalize

  def free
    return if @freed.state == :freed
    @freed.state = :freed
    Leptris::XML::FFI.leptris_document_free(@c_ptr) unless @c_ptr.nil?
    @c_ptr = nil
    @wrapper_cache&.clear
  end

  # Enable the first-party EXSLT-style extension pack on this
  # document: str:/set:/math: prefixed functions (replace, tokenize,
  # split, concat, padding; distinct, intersection, difference,
  # leading, trailing; max, min, abs, sqrt, power) as native C
  # handlers. Returns self for chaining.
  def exslt
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_exslt_enable(@c_ptr))
    self
  end

  # Document-level processing instructions (not tree nodes):
  # an array of [target, data] pairs in document order.
  def processing_instructions
    return @processing_instructions if @pi_version == @version
    count = Leptris::XML::FFI.leptris_document_pi_count(@c_ptr)
    result = count.times.map do |i|
      [Leptris::XML::FFI.leptris_document_pi_target(@c_ptr, i),
       Leptris::XML::FFI.read_pi_data(
         Leptris::XML::FFI.leptris_document_pi_data(@c_ptr, i)).to_s]
    end
    @processing_instructions = result
    @pi_version = @version
    result
  end

  # Removes a document-level processing instruction — by target
  # (String/Symbol) or by 0-based index among the document's PIs
  # (Integer) (libleptris 1.9.9, upstream #612). Returns the removed
  # PI — pool-owned and valid until #free — or nil when nothing
  # matched.
  def remove_pi(target_or_index)
    raise Leptris::XML::UseAfterFreeError if @freed.state == :freed
    if target_or_index.is_a?(Integer)
      ptr = Leptris::XML::FFI.leptris_document_remove_pi(
        @c_ptr, nil, target_or_index)
    else
      ptr = Leptris::XML::FFI.leptris_document_remove_pi(
        @c_ptr, target_or_index.to_s, 0)
    end
    return nil if ptr.null?
    @version += 1
    Leptris::XML::Node.wrap(ptr, self)
  end

  # Append a document-level processing instruction. Returns self.
  def add_pi(target, data = "")
    witness = Leptris::XML::FFI.leptris_document_add_pi(
      @c_ptr, target.to_s, data.to_s)
    raise Leptris::XML::Error, "leptris_document_add_pi failed" if witness.null?
    @version += 1
    self
  end

  # Marks the document read-only: tree mutations raise
  # Leptris::XML::ReadOnlyError, and read paths memoize aggressively
  # (names, content, children, attributes) since they can never go
  # stale. The C document is also frozen (advisory upstream). One-way.
  def readonly!
    Leptris::XML::FFI.leptris_document_freeze(@c_ptr)
    @readonly = true
    self
  end

  def readonly?
    @readonly == true
  end

  # True once #free has run (or the GC finalizer fired) — borrowed
  # handles check this before dereferencing their c_ptr.
  def freed?
    @freed.state == :freed || @c_ptr.nil?
  end

  # Document-level comments — parsed <!-- ... --> outside the
  # root element, prolog then epilog, in document order (the
  # companion reader to #processing_instructions; libleptris
  # 1.9.3, upstream #578). Version-memoized like the PI list.
  def comments
    return @comments if @comments_version == @version
    count = Leptris::XML::FFI.leptris_document_comment_count(@c_ptr)
    result = Array.new(count) do |i|
      Leptris::XML::FFI.leptris_document_comment_content(@c_ptr, i)
    end
    @comments = result
    @comments_version = @version
    result
  end

  # The thread-global last-failure [line, column] (1-based), or nil
  # when no error is recorded — the position companion to
  # Document#last_error; populated by recover parses.
  def last_error_position
    line = ::FFI::MemoryPointer.new(:int)
    column = ::FFI::MemoryPointer.new(:int)
    begin
      Leptris::XML::FFI.leptris_last_error_position(line, column)
      line.read_int.zero? && column.read_int.zero? ? nil :
        [line.read_int, column.read_int]
    ensure
      line.free
      column.free
    end
  end

  # The most recent error recorded against this document, or nil.
  def last_error
    msg = Leptris::XML::FFI.leptris_document_last_error(@c_ptr)
    msg.nil? || msg.empty? ? nil : msg
  end

  def name; "document"; end
  def document; self; end
  def encoding
    return nil if @c_ptr.nil?
    Leptris::XML::FFI.leptris_document_encoding(@c_ptr)
  end

  include Leptris::XML::Searchable
end
