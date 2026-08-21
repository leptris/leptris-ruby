# frozen_string_literal: true

class Taurus::XML::ProcessingInstruction < Taurus::XML::Node
  def name
    Taurus::XML::FFI.taurus_pi_node_get_target(@c_ptr)
  end
  alias_method :target, :name

  def content
    Taurus::XML::FFI.taurus_pi_node_get_data(@c_ptr).to_s
  end

  def target=(new_target)
    status = Taurus::XML::FFI.taurus_pi_node_set_target(@c_ptr, new_target.to_s)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    new_target
  end

  def data=(new_data)
    status = Taurus::XML::FFI.taurus_pi_node_set_data(@c_ptr, new_data.to_s)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    new_data
  end
end
