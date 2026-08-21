# frozen_string_literal: true

class Taurus::XML::DocType
  attr_reader :c_ptr, :document

  def initialize(c_ptr, document)
    @c_ptr = c_ptr
    @document = document
  end

  def name
    Taurus::XML::FFI.taurus_doctype_get_name(@c_ptr)
  end
  alias_method :node_name, :name

  def root_name
    Taurus::XML::FFI.taurus_doctype_get_root_name(@c_ptr)
  end

  def public_id
    Taurus::XML::FFI.taurus_doctype_get_public_id(@c_ptr)
  end

  def system_id
    Taurus::XML::FFI.taurus_doctype_get_system_id(@c_ptr)
  end

  def internal_subset
    Taurus::XML::FFI.taurus_doctype_get_internal_subset(@c_ptr)
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
