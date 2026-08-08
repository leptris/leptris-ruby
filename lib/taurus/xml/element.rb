# frozen_string_literal: true

class Taurus::XML::Element < Taurus::XML::Node
  def name
    Taurus::XML::FFI.taurus_element_name(@c_ptr)
  end
  alias_method :node_name, :name

  def name=(new_name)
    status = Taurus::XML::FFI.taurus_element_set_name(@c_ptr, new_name)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    new_name
  end
  alias_method :node_name=, :name=

  def content
    Taurus::XML::FFI.taurus_element_text(@c_ptr)
  end

  def content=(new_content)
    status = Taurus::XML::FFI.taurus_element_set_text(@c_ptr, new_content.to_s)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    new_content
  end

  def [](key)
    Taurus::XML::FFI.taurus_element_attribute(@c_ptr, key.to_s)
  end
  alias_method :attr, :[]
  alias_method :get_attribute, :[]

  def []=(key, value)
    status = Taurus::XML::FFI.taurus_element_set_attribute(@c_ptr, key.to_s, value.to_s)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    value
  end
  alias_method :set_attribute, :[]=

  def key?(name)
    !Taurus::XML::FFI.taurus_element_attribute(@c_ptr, name.to_s).nil?
  end
  alias_method :has_attribute?, :key?

  def remove_attribute(name)
    status = Taurus::XML::FFI.taurus_element_remove_attribute(@c_ptr, name.to_s)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    self
  end
  alias_method :delete, :remove_attribute

  def keys
    count = Taurus::XML::FFI.taurus_element_attribute_count(@c_ptr)
    count.times.map { |i| Taurus::XML::FFI.taurus_element_attribute_name_at(@c_ptr, i) }
  end

  def values
    count = Taurus::XML::FFI.taurus_element_attribute_count(@c_ptr)
    count.times.map { |i| Taurus::XML::FFI.taurus_element_attribute_value_at(@c_ptr, i) }
  end

  def attributes
    count = Taurus::XML::FFI.taurus_element_attribute_count(@c_ptr)
    result = {}
    count.times do |i|
      name = Taurus::XML::FFI.taurus_element_attribute_name_at(@c_ptr, i)
      value = Taurus::XML::FFI.taurus_element_attribute_value_at(@c_ptr, i)
      result[name] = Taurus::XML::Attr.new(name, value, self)
    end
    result
  end

  def attribute_nodes
    count = Taurus::XML::FFI.taurus_element_attribute_count(@c_ptr)
    count.times.map do |i|
      name = Taurus::XML::FFI.taurus_element_attribute_name_at(@c_ptr, i)
      value = Taurus::XML::FFI.taurus_element_attribute_value_at(@c_ptr, i)
      Taurus::XML::Attr.new(name, value, self)
    end
  end

  def add_child(node)
    status = Taurus::XML::FFI.taurus_element_append_child(@c_ptr, node.c_ptr)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    node
  end
  alias_method :<<, :add_child

  def prepend_child(node)
    status = Taurus::XML::FFI.taurus_element_prepend_child(@c_ptr, node.c_ptr)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    node
  end

  def add_next_sibling(node)
    status = Taurus::XML::FFI.taurus_element_insert_after(@c_ptr, node.c_ptr)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    node
  end

  def add_previous_sibling(node)
    status = Taurus::XML::FFI.taurus_element_insert_before(@c_ptr, node.c_ptr)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    node
  end

  def remove_child(node)
    status = Taurus::XML::FFI.taurus_element_remove_child(@c_ptr, node.c_ptr)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    node
  end

  def children=(node_or_nodes)
    # Remove existing children, then attach the new ones in source order.
    Taurus::XML::FFI.taurus_element_remove_children(@c_ptr)
    Array(node_or_nodes).each { |n| add_child(n) }
  end

  # Replace this element with +new_node+ in the parent's child list.
  # +new_node+ must belong to the same document. Returns +new_node+.
  def replace(new_node)
    parent = self.parent
    raise Taurus::XML::Error, "cannot replace a node with no parent" unless parent
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
      when Taurus::XML::Element then node_or_markup.dup
      when String
        frag_doc = Taurus::XML::Document.parse(node_or_markup)
        frag_doc.root or raise Taurus::XML::Error, "wrap markup has no root element"
      else
        raise ArgumentError, "wrap expects a String or Element, got #{node_or_markup.class}"
      end

    parent = self.parent
    raise Taurus::XML::Error, "cannot wrap a node with no parent" unless parent

    # Insert wrapper at self's position, then move self into wrapper.
    # add_child moves self (unlinks from old parent first), so no explicit
    # remove_child needed — and trying to remove after the move corrupts
    # the C tree (libtaurus silently handles non-child args badly).
    add_next_sibling(wrapper)
    wrapper.add_child(self)
    self
  end

  def dup
    raise NotImplementedError, "Element#dup requires taurus_element_copy (not yet exposed in v0.5.10 public API)"
  end

  def namespace
    uri = Taurus::XML::FFI.taurus_element_namespace(@c_ptr)
    return nil if uri.nil? || uri.empty?
    Taurus::XML::Namespace.new(self, uri)
  end

  def namespace_definitions
    count = Taurus::XML::FFI.taurus_element_namespace_count(@c_ptr)
    count.times.map do |i|
      prefix = Taurus::XML::FFI.taurus_element_namespace_decl_prefix(@c_ptr, i)
      uri = Taurus::XML::FFI.taurus_element_namespace_decl_uri(@c_ptr, i)
      Taurus::XML::Namespace.new(self, uri, prefix: prefix)
    end
  end

  def namespaces
    scopes = {}
    node = self
    while node.is_a?(Taurus::XML::Element)
      node.namespace_definitions.each do |ns|
        key = ns.prefix ? "xmlns:#{ns.prefix}" : "xmlns"
        scopes[key] ||= ns.href
      end
      node = node.parent
    end
    scopes
  end

  def to_xml(indent: 0, no_decl: false, encoding: nil)
    opts = Taurus::XML::FFI::SerializeOptions.new
    opts[:indent] = indent.to_i
    opts[:xml_declaration] = no_decl ? 0 : 1
    enc_ptr = nil
    if encoding
      enc_ptr = ::FFI::MemoryPointer.from_string(encoding.to_s)
      opts[:encoding] = enc_ptr
    end
    str_ptr = Taurus::XML::FFI.taurus_element_serialize(@c_ptr, opts.pointer)
    return "" if str_ptr.null?
    str_ptr.read_string.tap { Taurus::XML::FFI.taurus_free_string(str_ptr) }
  end

  def canonicalize(version = Taurus::XML::FFI::C14N_1_0,
                   inclusive_namespaces = nil,
                   with_comments: false,
                   exclusive: false,
                   mode: nil)
    resolved_mode = mode || (exclusive ? Taurus::XML::FFI::C14N_MODE_EXCLUSIVE
                                       : Taurus::XML::FFI::C14N_MODE_CANONICAL)
    ns_ptr, _anchor = Taurus::XML.c14n_build_ns_pointer(inclusive_namespaces)
    flags = with_comments ? 1 : 0
    str_ptr = Taurus::XML::FFI.taurus_c14n_canonicalize_subtree_ex(
      @c_ptr, version, resolved_mode, ns_ptr, flags)
    return "" if str_ptr.null?
    str_ptr.read_string.tap { Taurus::XML::FFI.taurus_free_string(str_ptr) }
  end
  alias_method :c14n, :canonicalize

  def add_namespace_definition(prefix, href)
    status = Taurus::XML::FFI.taurus_element_add_namespace_definition(
      @c_ptr, prefix.to_s, href.to_s)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    Taurus::XML::Namespace.new(self, href.to_s, prefix: prefix.nil? ? nil : prefix.to_s)
  end
  alias_method :add_namespace, :add_namespace_definition

  def default_namespace=(href)
    status = Taurus::XML::FFI.taurus_element_set_default_namespace(@c_ptr, href.to_s)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    href
  end

  def remove_namespace_definition(prefix)
    status = Taurus::XML::FFI.taurus_element_remove_namespace_definition(@c_ptr, prefix.to_s)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    self
  end
end
