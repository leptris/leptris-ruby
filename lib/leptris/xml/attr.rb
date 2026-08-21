# frozen_string_literal: true

# Lightweight attribute wrapper. libleptris v0.4.4 doesn't expose per-attribute
# pointers (no LeptrisAttribute accessors in the public API), so an Attr is a
# (name, value, parent_element) triple. Mutation goes through the parent
# element via #[]. Once upstream adds attribute-level accessors, this can
# become a pointer-backed wrapper.

class Leptris::XML::Attr
  attr_reader :name, :value, :element

  def initialize(name, value, element)
    @name = name
    @value = value
    @element = element
  end

  def value=(new_value)
    @element[@name] = new_value
    @value = new_value
  end

  def namespace
    nil  # upstream gap: per-attribute namespace not exposed
  end

  def remove
    @element.remove_attribute(@name)
  end

  def to_s; @value; end
  def to_str; @value; end

  def ==(other)
    other.is_a?(Leptris::XML::Attr) &&
      @name == other.name && @value == other.value &&
      @element == other.element
  end

  def inspect
    "#<#{self.class.name} name=#{@name.inspect} value=#{@value.inspect}>"
  end
end
