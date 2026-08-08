# frozen_string_literal: true

# libtaurus's TaurusNamespace is `const char*` (the URI directly). The Ruby
# Namespace wrapper holds (element, uri, optional prefix). When the prefix
# isn't supplied (e.g. via Element#namespace), it can be derived by walking
# the element's namespace declarations via taurus_element_namespace_decl_*.

class Taurus::XML::Namespace
  attr_reader :element, :href, :prefix

  def initialize(element, href, prefix: :derive)
    @element = element
    @href = href
    @prefix = prefix == :derive ? derive_prefix : prefix
  end

  def document
    @element&.document
  end

  def ==(other)
    other.is_a?(Taurus::XML::Namespace) &&
      @href == other.href && @prefix == other.prefix
  end

  def inspect
    "#<#{self.class.name} prefix=#{@prefix.inspect} href=#{@href.inspect}>"
  end

  private

  def derive_prefix
    return nil if @element.nil?
    count = Taurus::XML::FFI.taurus_element_namespace_count(@element.c_ptr)
    count.times do |i|
      uri = Taurus::XML::FFI.taurus_element_namespace_decl_uri(@element.c_ptr, i)
      next unless uri == @href
      prefix = Taurus::XML::FFI.taurus_element_namespace_decl_prefix(@element.c_ptr, i)
      return prefix.nil? || prefix.empty? ? nil : prefix
    end
    nil
  end
end
