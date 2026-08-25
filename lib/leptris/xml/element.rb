# frozen_string_literal: true

class Leptris::XML::Element < Leptris::XML::Node
  def name
    return @name if @name
    ensure_alive!
    @name = Leptris::XML::FFI.leptris_element_name(@c_ptr)
  end
  alias_method :node_name, :name

  def name=(new_name)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_set_name(@c_ptr, new_name))
    @name = new_name
  end
  alias_method :node_name=, :name=

  def content
    return @content if readonly_cached?(:@content)
    ensure_alive!
    Leptris::XML::FFI.leptris_element_text(@c_ptr).tap do |text|
      @content = text if @document&.readonly?
    end
  end

  def content=(new_content)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_set_text(@c_ptr, new_content.to_s))
    new_content
  end

  def [](key)
    ensure_alive!
    Leptris::XML::FFI.leptris_element_attribute(@c_ptr, key.to_s)
  end
  alias_method :attr, :[]
  alias_method :get_attribute, :[]

  def []=(key, value)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_set_attribute(@c_ptr, key.to_s, value.to_s))
    value
  end
  alias_method :set_attribute, :[]=

  def key?(name)
    ensure_alive!
    Leptris::XML::FFI.leptris_element_has_attribute(@c_ptr, name.to_s) != 0
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
      @c_ptr, uri&.to_s, local.to_s)
  end

  def has_attribute_ns?(uri, local)
    ensure_alive!
    Leptris::XML::FFI.leptris_element_has_attribute_ns(
      @c_ptr, uri&.to_s, local.to_s) != 0
  end

  def remove_attribute(name)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_remove_attribute(@c_ptr, name.to_s))
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
    attr = Leptris::XML::FFI.leptris_element_first_attribute(@c_ptr)
    until attr.nil? || attr.null?
      name = Leptris::XML::FFI.leptris_attribute_get_name(attr)
      value = Leptris::XML::FFI.leptris_attribute_get_value(@c_ptr, attr)
      yield Leptris::XML::Attr.new(name, value, self, c_handle: attr)
      attr = Leptris::XML::FFI.leptris_attribute_next(attr)
    end
    self
  end

  def keys
    return @keys if readonly_cached?(:@keys)
    result = each_attribute.to_a.map(&:name)
    @keys = result if @document&.readonly?
    result
  end

  def values
    return @values if readonly_cached?(:@values)
    result = each_attribute.to_a.map(&:value)
    @values = result if @document&.readonly?
    result
  end

  def attributes
    return @attributes if readonly_cached?(:@attributes)
    result = {}
    each_attribute { |attr| result[attr.name] = attr }
    @attributes = result if @document&.readonly?
    result
  end

  def attribute_nodes
    return @attribute_nodes if readonly_cached?(:@attribute_nodes)
    result = each_attribute.to_a
    @attribute_nodes = result if @document&.readonly?
    result
  end

  # The element's own namespace prefix (e.g. "foo" for <foo:child/>),
  # or nil when the element has none.
  def prefix
    ensure_alive!
    Leptris::XML::FFI.leptris_element_prefix(@c_ptr)
  end

  def prepend_child(node)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_prepend_child(@c_ptr, node.c_ptr))
    node
  end

  def add_next_sibling(node)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_insert_after(@c_ptr, node.c_ptr))
    node
  end

  def add_previous_sibling(node)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_insert_before(@c_ptr, node.c_ptr))
    node
  end

  def remove_child(node)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_remove_child(@c_ptr, node.c_ptr))
    node
  end

  def children=(node_or_nodes)
    ensure_writable!
    # Remove existing children, then attach the new ones in source order.
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_remove_children(@c_ptr))
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

  def dup
    copy_ptr = Leptris::XML::FFI.leptris_element_copy(@c_ptr, @document.c_ptr)
    raise Leptris::XML::Error, "leptris_element_copy failed" if copy_ptr.null?
    Leptris::XML::Node.wrap(copy_ptr, @document)
  end
  alias_method :clone, :dup

  def add_child(node_or_markup)
    ensure_writable!
    case node_or_markup
    when Leptris::XML::Node
      Leptris::XML::FFI.check_status(
        Leptris::XML::FFI.leptris_element_append_child(@c_ptr, node_or_markup.c_ptr))
      node_or_markup
    when String
      frag = Leptris::XML::DocumentFragment.parse(node_or_markup, @document)
      added = []
      frag.children.each do |n|
        Leptris::XML::FFI.check_status(
          Leptris::XML::FFI.leptris_element_append_child(@c_ptr, n.c_ptr))
        added << n
      end
      Leptris::XML::NodeSet.new(@document, added)
    else
      raise ArgumentError, "add_child expects a Node or String, got #{node_or_markup.class}"
    end
  end
  alias_method :<<, :add_child

  def namespace
    return @namespace if readonly_cached?(:@namespace)
    ensure_alive!
    uri = Leptris::XML::FFI.leptris_element_namespace(@c_ptr)
    result =
      if uri.nil? || uri.empty?
        nil
      else
        # The resolved namespace is reached via this element's own
        # prefix, so carry it through: consumers that distinguish
        # {"p" => "urn:p"} from the default {"nil => "urn:p"} need it.
        prefix = Leptris::XML::FFI.leptris_element_prefix(@c_ptr)
        prefix = nil if prefix.nil? || prefix.empty?
        Leptris::XML::Namespace.new(self, uri, prefix: prefix)
      end
    @namespace = result if @document&.readonly?
    result
  end

  def namespace_definitions
    return @namespace_definitions if readonly_cached?(:@namespace_definitions)
    ensure_alive!
    count = Leptris::XML::FFI.leptris_element_namespace_count(@c_ptr)
    result = count.times.map do |i|
      prefix = Leptris::XML::FFI.leptris_element_namespace_decl_prefix(@c_ptr, i)
      uri = Leptris::XML::FFI.leptris_element_namespace_decl_uri(@c_ptr, i)
      Leptris::XML::Namespace.new(self, uri, prefix: prefix)
    end
    @namespace_definitions = result if @document&.readonly?
    result
  end

  def namespaces
    return @namespaces if readonly_cached?(:@namespaces)
    scopes = {}
    node = self
    while node.is_a?(Leptris::XML::Element)
      node.namespace_definitions.each do |ns|
        key = ns.prefix ? "xmlns:#{ns.prefix}" : "xmlns"
        scopes[key] ||= ns.href
      end
      node = node.parent
    end
    @namespaces = scopes if @document&.readonly?
    scopes
  end

  def to_xml(indent: 0, no_decl: false, encoding: nil)
    Leptris::XML::Serialization.to_xml(
      Leptris::XML::FFI.method(:leptris_element_serialize_into), @c_ptr,
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
      Leptris::XML::FFI.method(:leptris_c14n_canonicalize_subtree_ex), @c_ptr,
      version: version, mode: resolved_mode,
      inclusive_namespaces: inclusive_namespaces,
      with_comments: with_comments)
  end
  alias_method :c14n, :canonicalize

  def add_namespace_definition(prefix, href)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_add_namespace_definition(
        @c_ptr, prefix.to_s, href.to_s))
    Leptris::XML::Namespace.new(self, href.to_s, prefix: prefix.nil? ? nil : prefix.to_s)
  end
  alias_method :add_namespace, :add_namespace_definition

  def default_namespace=(href)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_set_default_namespace(@c_ptr, href.to_s))
    href
  end

  def remove_namespace_definition(prefix)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_element_remove_namespace_definition(@c_ptr, prefix.to_s))
    self
  end
end
