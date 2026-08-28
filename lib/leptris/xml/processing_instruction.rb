# frozen_string_literal: true

class Leptris::XML::ProcessingInstruction < Leptris::XML::Node
  def name
    return @name if memo_hit?(@name_version)
    ensure_alive!
    result = Leptris::XML::FFI.leptris_pi_node_get_target(@c_ptr)
    if @document
      @name = result
      @name_version = @document.version
    end
    result
  end
  alias_method :target, :name

  def content
    return @content if memo_hit?(@content_version)
    ensure_alive!
    result = Leptris::XML::FFI.read_pi_data(
      Leptris::XML::FFI.leptris_pi_node_get_data(@c_ptr)).to_s
    if @document
      @content = result
      @content_version = @document.version
    end
    result
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
