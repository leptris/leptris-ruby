# frozen_string_literal: true

class Taurus::XML::CDATA < Taurus::XML::Text
  def name; "#cdata-section"; end

  def content
    Taurus::XML::FFI.taurus_cdata_node_get_content(@c_ptr)
  end

  def content=(new_content)
    status = Taurus::XML::FFI.taurus_cdata_node_set_content(@c_ptr, new_content.to_s)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    new_content
  end
end
