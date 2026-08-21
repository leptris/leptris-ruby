# frozen_string_literal: true

class Leptris::XML::ProcessingInstruction < Leptris::XML::Node
  def name
    Leptris::XML::FFI.leptris_pi_node_get_target(@c_ptr)
  end
  alias_method :target, :name

  def content
    Leptris::XML::FFI.leptris_pi_node_get_data(@c_ptr).to_s
  end

  def target=(new_target)
    status = Leptris::XML::FFI.leptris_pi_node_set_target(@c_ptr, new_target.to_s)
    raise Leptris::XML::Error,
      Leptris::XML::FFI.leptris_status_string(status) unless status == Leptris::XML::FFI::LEPTRIS_OK
    new_target
  end

  def data=(new_data)
    status = Leptris::XML::FFI.leptris_pi_node_set_data(@c_ptr, new_data.to_s)
    raise Leptris::XML::Error,
      Leptris::XML::FFI.leptris_status_string(status) unless status == Leptris::XML::FFI::LEPTRIS_OK
    new_data
  end
end
