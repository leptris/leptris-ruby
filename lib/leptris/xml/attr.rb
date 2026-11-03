# frozen_string_literal: true

# Lightweight attribute wrapper: a (name, value, parent_element)
# triple materialized from the attribute-iteration face, carrying
# the C attribute handle for the per-attribute namespace accessors.
# Mutation goes through the parent element via #[].

class Leptris::XML::Attr
  attr_reader :name, :value, :element

  # c_handle is the C LeptrisAttribute handle from the owning
  # element's iteration face — document-owned and borrowed. The rows
  # faces pass the raw Integer address (ruby#586 ask 2: no
  # per-attribute FFI::Pointer on read-only callers); the Pointer is
  # minted lazily on the first namespace read. Hand constructors may
  # pass a Pointer directly, or nil when constructed by hand.
  def initialize(name, value, element, c_handle: nil)
    @name = name
    @value = value
    @element = element
    @c_handle = c_handle
  end

  def value=(new_value)
    @element[@name] = new_value
    @value = new_value
  end

  # The prefix as written in the qualified name (bytes before the
  # colon), nil for a no-namespace attribute. Name-derived and
  # immutable — the same semantics as leptris_attribute_prefix, so
  # no declaration lookup is involved.
  def prefix
    i = @name.index(":")
    i ? @name[0, i] : nil
  end

  # The attribute's namespace URI, resolved through the OWNING
  # element's in-scope declarations at read time (libleptris 1.8.0).
  # nil for a no-namespace attribute or an undeclared prefix; xml
  # is prebound to http://www.w3.org/XML/1998/namespace.
  def namespace_uri
    h = c_handle_ptr
    return nil if h.nil?
    Leptris::XML::FFI.leptris_attribute_namespace_uri(h)
  end

  def namespace
    namespace_uri
  end

  def remove
    @element.remove_attribute(@name)
  end

  def to_s; @value; end
  def to_str; @value; end

  # Serialized attribute form: name="value" with the five XML special
  # characters escaped in the value — single pass, no chained gsubs.
  ESCAPE_TABLE = {
    "&" => "&amp;", "<" => "&lt;", ">" => "&gt;",
    '"' => "&quot;", "'" => "&apos;",
  }.freeze
  private_constant :ESCAPE_TABLE

  def to_xml
    "#{@name}=\"#{@value.to_s.gsub(/[&<>"']/, ESCAPE_TABLE)}\""
  end

  def ==(other)
    other.is_a?(Leptris::XML::Attr) &&
      @name == other.name && @value == other.value &&
      @element == other.element
  end

  def inspect
    "#<#{self.class.name} name=#{@name.inspect} value=#{@value.inspect}>"
  end

  private

  # Wrap a raw Integer address on first namespace read; Pointer and
  # nil pass through unchanged.
  def c_handle_ptr
    if @c_handle.is_a?(Integer)
      @c_handle = @c_handle.zero? ? nil : FFI::Pointer.new(@c_handle)
    end
    @c_handle
  end
end
