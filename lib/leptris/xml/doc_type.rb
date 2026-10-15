# frozen_string_literal: true

class Leptris::XML::DocType
  attr_reader :c_ptr, :document

  def initialize(c_ptr, document, detached_name: nil,
                 detached_public_id: nil, detached_system_id: nil)
    @c_ptr = c_ptr
    @document = document
    @detached_name = detached_name
    @detached_public_id = detached_public_id
    @detached_system_id = detached_system_id
  end

  # Detached token (leptris-ruby#459 ask 2): create first, attach
  # later via Document#add_child — the two-phase facade contract.
  def self.new_detached(document, name, public_id = nil, system_id = nil)
    new(nil, document, detached_name: name.to_s,
        detached_public_id: public_id, detached_system_id: system_id)
  end

  def attached?
    !@c_ptr.nil?
  end

  # Installs the C node handle on a detached token (Document#add_child
  # routes the attach). The detached field copies die here.
  def attach!(c_ptr)
    @c_ptr = c_ptr
    @detached_name = nil
    @detached_public_id = nil
    @detached_system_id = nil
    self
  end

  def name
    return @detached_name if @c_ptr.nil?
    Leptris::XML::FFI.leptris_doctype_get_name(c_ptr)
  end
  alias_method :node_name, :name

  def root_name
    return @detached_name if @c_ptr.nil?
    Leptris::XML::FFI.leptris_doctype_get_root_name(c_ptr)
  end

  def public_id
    return @detached_public_id if @c_ptr.nil?
    Leptris::XML::FFI.leptris_doctype_get_public_id(c_ptr)
  end

  def system_id
    return @detached_system_id if @c_ptr.nil?
    Leptris::XML::FFI.leptris_doctype_get_system_id(c_ptr)
  end

  def internal_subset
    Leptris::XML::FFI.leptris_doctype_get_internal_subset(c_ptr)
  end

  def external_id
    pub = public_id
    sys = system_id
    return nil if pub.nil? && sys.nil?
    parts = []
    parts << "PUBLIC \"#{pub}\"" if pub
    parts << "SYSTEM \"#{sys}\"" if sys && pub.nil?
    parts << "\"#{sys}\"" if pub && sys
    parts.join(" ")
  end

  def to_s
    inner = internal_subset
    parts = ["<!DOCTYPE #{name}"]
    parts << external_id if external_id
    parts << "[#{inner}]" if inner && !inner.empty?
    parts.join(" ") + ">"
  end

  def inspect
    "#<#{self.class.name} name=#{name.inspect} public=#{public_id.inspect} system=#{system_id.inspect}>"
  end
end
