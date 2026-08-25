# frozen_string_literal: true

class Leptris::XML::ProcessingInstruction < Leptris::XML::Node
  def name
    return @name if readonly_cached?(:@name)
    Leptris::XML::FFI.leptris_pi_node_get_target(@c_ptr).tap do |target|
      @name = target if @document&.readonly?
    end
  end
  alias_method :target, :name

  def content
    return @content if readonly_cached?(:@content)
    Leptris::XML::FFI.leptris_pi_node_get_data(@c_ptr).to_s.tap do |data|
      @content = data if @document&.readonly?
    end
  end

  def target=(new_target)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_pi_node_set_target(@c_ptr, new_target.to_s))
    new_target
  end

  def data=(new_data)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_pi_node_set_data(@c_ptr, new_data.to_s))
    new_data
  end
end
