# frozen_string_literal: true

class Leptris::XML::Element < Leptris::XML::Node
  # TODO.perf/01: with the native bundle loaded, hot reads go
  # through the ext (one C-API dispatch + rb_str_new_cstr — no FFI
  # marshaling; ~3x per read). defined? is near-free when absent.
  # Scope-owned (iterparse-yield) elements stay on the FFI path:
  # their pool addresses recycle across yields and their lifetime
  # rules ride the IterationScope seam — the ext fast path is for
  # document-owned trees.
  def native_fast?
    @native_fast
  end

  def name
    return @name if @name
    ensure_alive!
    @name = if @addr_reads_fast
              Leptris::XML::Native.fast_name(@c_address)
            else
              Leptris::XML::FFI.leptris_element_name(c_ptr)
            end
  end
  alias_method :node_name, :name

  def name=(new_name)
    if @native_fast
      Leptris::XML::Native.set_binding_name(
        @document, @c_address, new_name)
      return @name = new_name
    end
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_set_name(c_ptr, new_name))
    @name = new_name
  end
  alias_method :node_name=, :name=

  def content
    return @content if memo_hit?(@content_version)
    ensure_alive!
    result = if @addr_reads_fast
               Leptris::XML::Native.fast_element_text(@c_address)
             else
               Leptris::XML::FFI.leptris_element_text(c_ptr)
             end
    if @document
      @content = result
      @content_version = @document.version
    end
    result
  end

  def content=(new_content)
    if @native_fast
      Leptris::XML::Native.set_binding_text(
        @document, @c_address, new_content.to_s)
      @content = new_content.to_s
      @content_version = @document.version if @document
      return new_content
    end
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_set_text(c_ptr, new_content.to_s))
    @content = new_content.to_s
    @content_version = @document.version if @document
    new_content
  end

  def [](key)
    # BARE names serve from the versioned attributes hash (written
    # name == the only legal key for a no-namespace attribute);
    # materializes on demand, invalidates through the mutation gate
    # (ADR 0003's 1.9.14 extension); a hash read cannot
    # use-after-free. QUALIFIED names (with a colon) go to the
    # engine: they resolve through in-scope declarations, where the
    # written prefix never matters — the hash cannot answer them.
    #
    # Cold single-attribute reads (ruby#150): the previous path
    # materialised EVERY attribute into two hashes on the first
    # bare read (~17 allocs on a 2-attr element). Now a cold miss
    # pays ONE FFI call and fills only that name; subsequent
    # same-name reads hit the hash; a later attributes/keys call
    # rebuilds the full face. Full-memo (@attributes set) still
    # answers misses as nil without another FFI.
    name = key.to_s
    if @document && !name.include?(":")
      values = @attr_values
      if values && @attributes_version == @document.version
        v = values[name]
        # Present, or a FULL-memo miss (absent). A partial-memo nil
        # is ambiguous (un-queried vs absent) — one idempotent
        # engine call resolves it, then the name is cached.
        return v if !v.nil? || @attributes
        ensure_alive!
        v = if @addr_reads_fast
                 Leptris::XML::Native.fast_attribute(@c_address, name)
               else
                 Leptris::XML::FFI.leptris_element_attribute(c_ptr, name)
               end
        values[name] = v
        return v
      end
      # Completely cold: one read, start a partial values hash.
      # Drop any full-face memos from a prior version — otherwise a
      # post-mutation cold [] would stamp the new version onto a
      # stale @attributes hash and attributes would serve it.
      ensure_alive!
      v = if @addr_reads_fast
            Leptris::XML::Native.fast_attribute(@c_address, name)
          else
            Leptris::XML::FFI.leptris_element_attribute(c_ptr, name)
          end
      @attr_values = { name => v }
      @attributes = nil
      @attribute_nodes = nil
      @keys = nil
      @values = nil
      @attributes_version = @document.version
      return v
    end
    ensure_alive!
    v = Leptris::XML::FFI.leptris_element_attribute(c_ptr, name)
    # Namespace-aware misses (an undeclared prefix never resolves
    # through in-scope declarations) fall back to the WRITTEN name
    # — the same flat face #attributes exposes, so a value written
    # as el["n:x"] reads back through el["n:x"] (#161).
    return v unless v.nil?
    attributes[name]&.value
  end
  alias_method :attr, :[]
  alias_method :get_attribute, :[]

  def []=(key, value)
    # C-bound write (TODO.perf/11): gates + version bump + engine
    # set in one dispatch; the bump drops the version-stamped
    # attribute memos on both surfaces.
    if native_fast_children?
      Leptris::XML::Native.set_binding_attribute(
        @document, @c_address, key.to_s, value.to_s)
      seed_attribute_memo(key.to_s, value.to_s)
      return value
    end
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_set_attribute(c_ptr, key.to_s, value.to_s))
    seed_attribute_memo(key.to_s, value.to_s)
    value
  end
  alias_method :set_attribute, :[]=

  # TODO.perf/26: the write knows the new value — seed the
  # version-stamped memo so a read-back skips re-derivation. A
  # valid-and-just-invalidated partial memo extends in place; a
  # full face (or anything older) restarts partial, mirroring the
  # cold-[] rules.
  def seed_attribute_memo(name, written)
    return unless @document
    values = @attr_values
    if values && !@attributes &&
       @attributes_version == @document.version - 1
      values[name] = written
    else
      @attr_values = { name => written }
      @attributes = nil
      @attribute_nodes = nil
      @keys = nil
      @values = nil
    end
    @attributes_version = @document.version
  end
  private :seed_attribute_memo

  def key?(name)
    ensure_alive!
    # Versioned attribute memo first (TODO.perf/21): a hit proves
    # presence without the engine round-trip; the memo cannot
    # prove absence for a partial fill, so misses fall through.
    n = name.to_s
    values = @attr_values
    if @document && values && @attributes_version == @document.version &&
       values.key?(n)
      return true
    end
    return true if Leptris::XML::FFI.leptris_element_has_attribute(
      c_ptr, n) != 0
    # Same written-name fallback as #[] — the engine lookup is
    # namespace-aware and misses undeclared prefixes (#161).
    attributes.key?(n)
  end
  alias_method :has_attribute?, :key?

  # Expanded-name attribute access (libleptris 1.8.0): URI + local
  # name with XML Namespaces 1.0 semantics — the written prefix
  # never matters, only what it resolves to through this element's
  # in-scope declarations. uri nil/"" matches no-namespace
  # attributes only; xmlns declarations are invisible.
  def attribute_ns(uri, local)
    ensure_alive!
    Leptris::XML::FFI.leptris_element_attribute_ns(
      c_ptr, uri&.to_s, local.to_s)
  end

  def has_attribute_ns?(uri, local)
    ensure_alive!
    Leptris::XML::FFI.leptris_element_has_attribute_ns(
      c_ptr, uri&.to_s, local.to_s) != 0
  end

  def remove_attribute(name)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_remove_attribute(c_ptr, name.to_s))
    self
  end
  alias_method :delete, :remove_attribute

  # Iterates the element's attributes via the v1.1.0 linked-list face
  # (one FFI call per attribute; the name_at/value_at indexing API
  # re-walks the list per index, making it O(n^2) per element).
  # The C attribute handle rides along so Attr can serve the
  # per-attribute namespace accessors (libleptris 1.8.0).
  def each_attribute
    return enum_for(:each_attribute) unless block_given?
    ensure_alive!
    attr = Leptris::XML::FFI.leptris_element_first_attribute(c_ptr)
    until attr.nil? || attr.null?
      name = Leptris::XML::FFI.leptris_attribute_get_name(attr)
      value = Leptris::XML::FFI.leptris_attribute_get_value(c_ptr, attr)
      yield Leptris::XML::Attr.new(name, value, self, c_handle: attr)
      attr = Leptris::XML::FFI.leptris_attribute_next(attr)
    end
    self
  end

  def keys
    return @keys if memo_hit?(@keys_version)
    result = each_attribute.to_a.map(&:name)
    if @document
      @keys = result
      @keys_version = @document.version
    end
    result
  end

  def values
    return @values if memo_hit?(@values_version)
    result = each_attribute.to_a.map(&:value)
    if @document
      @values = result
      @values_version = @document.version
    end
    result
  end

  def attributes
    # Require the full Attr-hash face — a cold [] may have set the
    # version with only a partial @attr_values (ruby#150).
    return @attributes if @attributes && memo_hit?(@attributes_version)
    # TODO.perf/28: the bulk faces touch no document state —
    # scope-eligible via @addr_reads_fast.
    if @addr_reads_fast
      # TODO.perf/10: both memo faces in one C walk.
      result, values = Leptris::XML::Native.bulk_attr_faces(
        @c_address, self)
      if @document
        @attributes = result
        @attr_values = values
        @attributes_version = @document.version
      end
      return result
    end
    result = {}
    values = {}
    each_attribute do |attr|
      result[attr.name] = attr
      values[attr.name] = attr.value
    end
    if @document
      @attributes = result
      @attr_values = values
      @attributes_version = @document.version
    end
    result
  end

  # Read-only attribute listing as [name, value] pairs — no Attr
  # objects. Names are interned frozen strings (shared across
  # documents; dup before mutating), values fresh UTF-8 strings.
  # Document order, duplicates included. One C crossing per element
  # on the native layer (leptris-ruby#278) — the walk-hot shape for
  # consumers that only read name/value. Mutation and per-attribute
  # namespace resolution stay on attribute_nodes.
  def attribute_pairs
    ensure_alive!
    return @attribute_pairs if memo_hit?(@attribute_pairs_version)
    result = if @c_address && @document &&
                ::Leptris::XML::Native.respond_to?(:attribute_pairs)
                ::Leptris::XML::Native.attribute_pairs(@document, @c_address)
                    .each_slice(2).to_a
              else
                each_attribute.to_a.map { |a| [a.name, a.value] }
              end
    if @document
      @attribute_pairs = result
      @attribute_pairs_version = @document.version
    end
    result
  end

  def attribute_nodes
    return @attribute_nodes if memo_hit?(@attribute_nodes_version)
    result = each_attribute.to_a
    if @document
      @attribute_nodes = result
      @attribute_nodes_version = @document.version
    end
    result
  end

  # The element's own namespace prefix (e.g. "foo" for <foo:child/>),
  # or nil when the element has none.
  def prefix
    ensure_alive!
    if native_fast?
      Leptris::XML::Native.fast_prefix(@c_address)
    else
      result = Leptris::XML::FFI.leptris_element_prefix(c_ptr)
      result if result && !result.empty?
    end
  end

  # The written qualified name — "foo:child" with a prefix, the
  # bare local name without. The explicit contract behind the
  # #name/#prefix split: #name answers the local part, the
  # serialized form uses this spelling (#161).
  def qualified_name
    p = prefix
    p ? "#{p}:#{name}" : name
  end

  # Cross-document and cross-scope adoption (#178 ask 1): the
  # engine's attach entries move a subtree but do not lift the
  # source's in-scope namespace declarations, so serialized output
  # can carry undeclared prefixes. Re-declares on +node+ everything
  # from its in-scope set that +target_scope+ (the attach target's
  # in-scope map) does not already resolve identically — the
  # declarations ride the moved element, staying local to the
  # adopted subtree. Call BEFORE attaching: the source scope is
  # read through the node's current ancestors. Identical scopes
  # (the common same-document move) add nothing.
  # TODO.perf/09: one dispatch answers whether ANY lift work can
  # apply (no resolved namespace, no own declarations = provable
  # no-op — the common programmatic-build shape). Checked at the
  # mutation sites so the target's in-scope namespaces are never
  # materialized when the answer is no.
  def self.skip_adoption_lift?(node)
    # Non-elements can never need a lift (lift's own first line
    # no-ops them) — skipping also avoids materializing the
    # target's namespaces for the text/comment children every
    # build appends.
    return true unless node.is_a?(Leptris::XML::Element)
    return false unless defined?(Leptris::XML::NATIVE_FAST)
    !Leptris::XML::Native.ns_lift_needed?(node.c_ptr.address)
  end

  def self.lift_namespaces_for_adoption(node, target_scope)
    return unless node.is_a?(Leptris::XML::Element)
    # Declarations the node already carries (its own definitions —
    # preserved by the C copy and by moves) ride it as-is; lifting
    # must not duplicate them, only what came from ANCESTORS.
    own = node.namespace_definitions.each_with_object({}) do |ns, h|
      h[ns.prefix ? "xmlns:#{ns.prefix}" : "xmlns"] = ns.href
    end
    node.namespaces.each do |key, uri|
      next if target_scope[key] == uri || own[key] == uri
      prefix = key.start_with?("xmlns:") ? key.delete_prefix("xmlns:") : nil
      node.add_namespace_definition(prefix, uri)
    end
    # libxml2 reparent parity (moxml #208 lineage): an OWN
    # declaration the attach target already resolves identically
    # is redundant — prune it so serialized output does not
    # re-declare (libxml2 drops these on reparent). Shadowing
    # declarations (same prefix, different URI) are preserved.
    node.namespace_definitions.each do |ns|
      key = ns.prefix ? "xmlns:#{ns.prefix}" : "xmlns"
      next unless target_scope[key] == ns.href
      node.remove_namespace_definition(ns.prefix)
    end
    nil
  end

  def prepend_child(node)
    # C-bound insert (TODO.perf/14): gates + predicate + version
    # bump + engine insert in one dispatch; Qnil = the child needs
    # the namespace lift — the full path below handles it.
    if native_fast_children?
      unless Leptris::XML::Native.insert_binding_child(
        @document, @c_address, node.c_ptr.address, 1).nil?
        Leptris::XML::Node.invalidate_cross_document!(node, @document)
        return node
      end
    end
    ensure_writable!
    unless Leptris::XML::Element.skip_adoption_lift?(node)
      Leptris::XML::Element.lift_namespaces_for_adoption(node, namespaces)
    end
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_prepend_child(c_ptr, node.c_ptr))
    Leptris::XML::Node.invalidate_cross_document!(node, @document)
    node
  end

  def add_next_sibling(node)
    # C-bound insert (TODO.perf/14): gates + predicate + version
    # bump + engine insert in one dispatch; Qnil = the child needs
    # the namespace lift — the full path below handles it.
    if native_fast_children?
      unless Leptris::XML::Native.insert_binding_child(
        @document, @c_address, node.c_ptr.address, 2).nil?
        Leptris::XML::Node.invalidate_cross_document!(node, @document)
        return node
      end
    end
    ensure_writable!
    unless Leptris::XML::Element.skip_adoption_lift?(node)
      Leptris::XML::Element.lift_namespaces_for_adoption(node, namespaces)
    end
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_insert_after(c_ptr, node.c_ptr))
    Leptris::XML::Node.invalidate_cross_document!(node, @document)
    node
  end

  def add_previous_sibling(node)
    # C-bound insert (TODO.perf/14): gates + predicate + version
    # bump + engine insert in one dispatch; Qnil = the child needs
    # the namespace lift — the full path below handles it.
    if native_fast_children?
      unless Leptris::XML::Native.insert_binding_child(
        @document, @c_address, node.c_ptr.address, 3).nil?
        Leptris::XML::Node.invalidate_cross_document!(node, @document)
        return node
      end
    end
    ensure_writable!
    unless Leptris::XML::Element.skip_adoption_lift?(node)
      Leptris::XML::Element.lift_namespaces_for_adoption(node, namespaces)
    end
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_insert_before(c_ptr, node.c_ptr))
    Leptris::XML::Node.invalidate_cross_document!(node, @document)
    node
  end

  def remove_child(node)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_remove_child(c_ptr, node.c_ptr))
    node
  end

  def children=(node_or_nodes)
    ensure_writable!
    # Remove existing children, then attach the new ones in source order.
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_remove_children(c_ptr))
    Array(node_or_nodes).each { |n| add_child(n) }
  end

  # Replace this element with +new_node+ in the parent's child list.
  # +new_node+ must belong to the same document. Returns +new_node+.
  def replace(new_node)
    parent = self.parent
    raise Leptris::XML::Error, "cannot replace a node with no parent" unless parent
    add_next_sibling(new_node)
    parent.remove_child(self)
    new_node
  end

  # Like #replace but returns self for chaining.
  def swap(new_node)
    replace(new_node)
    self
  end

  # Wrap this element in a new element parsed from +markup+ or a dup of
  # +node+. The wrapper takes this element's place in the tree, and this
  # element becomes its only child. Returns self for chaining.
  def wrap(node_or_markup)
    wrapper =
      case node_or_markup
      when Leptris::XML::Element then node_or_markup.dup
      when String
        frag_doc = Leptris::XML::Document.parse(node_or_markup)
        frag_doc.root or raise Leptris::XML::Error, "wrap markup has no root element"
      else
        raise ArgumentError, "wrap expects a String or Element, got #{node_or_markup.class}"
      end

    parent = self.parent
    raise Leptris::XML::Error, "cannot wrap a node with no parent" unless parent

    # Insert wrapper at self's position, then move self into wrapper.
    # add_child moves self (unlinks from old parent first), so no explicit
    # remove_child needed — and trying to remove after the move corrupts
    # the C tree (libleptris silently handles non-child args badly).
    add_next_sibling(wrapper)
    wrapper.add_child(self)
    self
  end

  # Deep copy in a NEW document via Document.copy_of (the single
  # copy seam — every child kind and namespace survives,
  # #696/#721/#812). TODO.perf/30: one C dispatch when the ext
  # is loaded — the namespace-lift decision stays here.
  def dup
    ensure_alive!
    if @addr_reads_fast
      doc = Leptris::XML::Native.copy_binding_element(
        @document, @c_address)
      unless doc.nil?
        copied = doc.root
        unless Leptris::XML::Element.skip_adoption_lift?(copied)
          Leptris::XML::Element.lift_namespaces_for_adoption(copied, {})
        end
        return copied
      end
    end
    Leptris::XML::Document.copy_of(self)
  end
  alias_method :clone, :dup

  # Fused create+append (libleptris 1.9.153): builds a child
  # element of +name+ in this element's document and attaches it
  # in ONE C call — the builder-shape single call
  # (leptris_element_create_child). Tree semantics identical to
  # document.create_element(name) + add_child.
  def create_child(name)
    ensure_writable!
    ptr = Leptris::XML::FFI.leptris_element_create_child(c_ptr, name.to_s)
    raise Leptris::XML::Error,
      "leptris_element_create_child failed for #{name.inspect}" if ptr.null?
    Leptris::XML::Node.wrap_fresh(ptr, @document, Leptris::XML::FFI::NODE_ELEMENT)
  end

  def add_child(node_or_markup)
    ensure_writable!
    case node_or_markup
    when Leptris::XML::Node
      # C-bound append (TODO.perf/08-09): one dispatch runs the
      # readonly/liveness gates, the provable no-op lift
      # predicate, the version bump, and the engine append. Qnil
      # means the child needs the namespace lift — fall through
      # to the full path.
      if native_fast_children?
        # The face raises on failure (TODO.perf/36); Qnil = the
        # child needs the lift — the full path handles it.
        unless Leptris::XML::Native.append_binding_child(
          @document, @c_address, node_or_markup.c_ptr.address).nil?
          Leptris::XML::Node.invalidate_cross_document!(node_or_markup, @document)
          return node_or_markup
        end
      end
      unless Leptris::XML::Element.skip_adoption_lift?(node_or_markup)
        Leptris::XML::Element.lift_namespaces_for_adoption(node_or_markup, namespaces)
      end
      Leptris::XML::FFI.check_status(
        Leptris::XML::FFI.leptris_element_append_child(c_ptr, node_or_markup.c_ptr))
      Leptris::XML::Node.invalidate_cross_document!(node_or_markup, @document)
      node_or_markup
    when String
      # TODO.perf/34: one dispatch parses the markup and appends
      # every fragment child (single gate + bump). Negative
      # returns: -1 re-runs the FFI path for the exact parse
      # error; -1000-st routes through check_status.
      if native_fast_children?
        r = Leptris::XML::Native.append_markup(
          @document, @c_address, node_or_markup)
        if r != -1
          # Appends raise in C on status failures (TODO.perf/36);
          # -1 alone means the parse failed.
          return Leptris::XML::NodeSet.new(@document, []) if r.zero?
          return Leptris::XML::NodeSet.new(@document, last_added(r))
        end
        # parse failure: reproduce the exact error via the legacy
        # path (it re-fails fast)
        Leptris::XML::DocumentFragment.parse(node_or_markup, @document)
      end
      frag = Leptris::XML::DocumentFragment.parse(node_or_markup, @document)
      added = []
      frag.children.each do |n|
        Leptris::XML::FFI.check_status(
          Leptris::XML::FFI.leptris_element_append_child(c_ptr, n.c_ptr))
        added << n
      end
      Leptris::XML::NodeSet.new(@document, added)
    else
      raise ArgumentError, "add_child expects a Node or String, got #{node_or_markup.class}"
    end
  end
  # The markup-append face appends in fragment order; the added
  # nodes are this element's last +count+ children.
  def last_added(count)
    kids = children.to_a
    kids.last(count)
  end
  private :last_added

  alias_method :<<, :add_child

  def namespace
    return @namespace if memo_hit?(@namespace_version)
    ensure_alive!
    uri = Leptris::XML::FFI.leptris_element_namespace(c_ptr)
    result =
      if uri.nil? || uri.empty?
        nil
      else
        # The resolved namespace is reached via this element's own
        # prefix, so carry it through: consumers that distinguish
        # {"p" => "urn:p"} from the default {"nil => "urn:p"} need it.
        prefix = Leptris::XML::FFI.leptris_element_prefix(c_ptr)
        prefix = nil if prefix.nil? || prefix.empty?
        Leptris::XML::Namespace.new(self, uri, prefix: prefix)
      end
    if @document
      @namespace = result
      @namespace_version = @document.version
    end
    result
  end

  # Nokogiri node.namespace= semantics (libleptris 1.9.76, #817):
  # nil (or "") detaches the namespace — the resolved link and the
  # name's prefix clear, and an xmlns="" undeclaration blocks
  # in-scope defaults from capturing the unqualified name. A URI
  # rebinds to an in-scope declaration carrying it (adopting its
  # prefix); a URI with no in-scope declaration raises — declare
  # it first with #add_namespace_definition.
  def namespace=(uri)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_set_namespace(c_ptr, uri&.to_s))
    uri
  end

  # The local name, prefix, and resolved namespace URI in ONE
  # call (libleptris 1.9.144) — the adapter fan-out read.
  # Equivalent to #name + #prefix + #namespace, single entry.
  def expanded_name
    ensure_alive!
    local = ::FFI::MemoryPointer.new(:pointer)
    prefix = ::FFI::MemoryPointer.new(:pointer)
    uri = ::FFI::MemoryPointer.new(:pointer)
    Leptris::XML::FFI.leptris_element_expanded_name(
      c_ptr, local, prefix, uri)
    local_ptr = local.read_pointer
    prefix_ptr = prefix.read_pointer
    uri_ptr = uri.read_pointer
    result = {
      local: local_ptr.read_string,
      prefix: prefix_ptr.null? ? nil : prefix_ptr.read_string,
      namespace_uri: uri_ptr.null? ? nil : uri_ptr.read_string,
    }
    local.free
    prefix.free
    uri.free
    result
  end

  def namespace_definitions
    return @namespace_definitions if memo_hit?(@namespace_definitions_version)
    ensure_alive!
    count = Leptris::XML::FFI.leptris_element_namespace_count(c_ptr)
    result = count.times.map do |i|
      prefix = Leptris::XML::FFI.leptris_element_namespace_decl_prefix(c_ptr, i)
      uri = Leptris::XML::FFI.leptris_element_namespace_decl_uri(c_ptr, i)
      Leptris::XML::Namespace.new(self, uri, prefix: prefix)
    end
    if @document
      @namespace_definitions = result
      @namespace_definitions_version = @document.version
    end
    result
  end

  def namespaces
    return @namespaces if memo_hit?(@namespaces_version)
    scopes = {}
    node = self
    while node.is_a?(Leptris::XML::Element)
      node.namespace_definitions.each do |ns|
        key = ns.prefix ? "xmlns:#{ns.prefix}" : "xmlns"
        scopes[key] ||= ns.href
      end
      # unstamped: this walk also runs inside the adoption lift,
      # between the version bump and the engine move (see
      # Node#unstamped_parent).
      node = node.unstamped_parent
    end
    if @document
      @namespaces = scopes
      @namespaces_version = @document.version
    end
    scopes
  end

  # The serialized children (Nokogiri parity): elements serialize
  # through the engine (correct escaping), text is XML-escaped,
  # comments/CDATA/PIs render their literal forms. The complement
  # of #inner_text, which returns the unescaped text content.
  def inner_html
    ensure_alive!
    # One C pass (TODO.perf/18): the child chain, per-kind
    # serialization, and the escape set all in one dispatch —
    # byte-identical to the Ruby loop below.
    return Leptris::XML::Native.fast_inner_xml(@c_address) if
      @native_fast
    children.map do |child|
      case child
      when Leptris::XML::Element
        Leptris::XML::Serialization.element_xml_default(child.c_ptr)
      when Leptris::XML::CDATA # before Text: CDATA subclasses it
        "<![CDATA[#{child.content}]]>"
      when Leptris::XML::Text
        Leptris::XML::Serialization.escape_text(child.content)
      when Leptris::XML::Comment then "<!--#{child.content}-->"
      when Leptris::XML::ProcessingInstruction
        data = child.content
        data.empty? ? "<?#{child.name}?>" : "<?#{child.name} #{data}?>"
      else
        Leptris::XML::Serialization.escape_text(child.content.to_s)
      end
    end.join
  end

  # indent_text: a STRING is the indent unit with Nokogiri's
  # semantics (leptris-ruby#109; via a C-side copy into a fresh
  # document — no element-level ext entry exists yet). true is NOT
  # supported here: the display form is document-level.
  def to_xml(indent: 0, no_decl: false, encoding: nil, indent_text: false,
              expand_empty: false)
    ensure_alive!
    if indent_text == true
      raise ArgumentError,
        "indent_text: true (display form) is document-level — " \
        "pass the unit string for elements"
    end
    return Leptris::XML::Serialization.to_xml_element_unit(
      self, indent_text, indent: indent) if indent_text.is_a?(String)
    return Leptris::XML::Serialization.element_xml_expand_empty(c_ptr) if expand_empty
    Leptris::XML::Serialization.to_xml(
      Leptris::XML::Serialization::ELEMENT_SERIALIZE_INTO, c_ptr,
      indent: indent, no_decl: no_decl, encoding: encoding)
  end

  def canonicalize(version = Leptris::XML::FFI::C14N_1_0,
                   inclusive_namespaces = nil,
                   with_comments: false,
                   exclusive: false,
                   mode: nil)
    resolved_mode = mode || (exclusive ? Leptris::XML::FFI::C14N_MODE_EXCLUSIVE
                                       : Leptris::XML::FFI::C14N_MODE_CANONICAL)
    Leptris::XML::Serialization.canonicalize(
      Leptris::XML::FFI.method(:leptris_c14n_canonicalize_subtree_ex), c_ptr,
      version: version, mode: resolved_mode,
      inclusive_namespaces: inclusive_namespaces,
      with_comments: with_comments)
  end
  alias_method :c14n, :canonicalize

  def add_namespace_definition(prefix, href)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_add_namespace_definition(
        c_ptr, prefix.to_s, href.to_s))
    Leptris::XML::Namespace.new(self, href.to_s, prefix: prefix.nil? ? nil : prefix.to_s)
  end
  alias_method :add_namespace, :add_namespace_definition

  def default_namespace=(href)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_set_default_namespace(c_ptr, href.to_s))
    href
  end

  def remove_namespace_definition(prefix)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_remove_namespace_definition(c_ptr, prefix.to_s))
    self
  end
end
