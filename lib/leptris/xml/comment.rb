# frozen_string_literal: true

class Leptris::XML::Comment < Leptris::XML::Node
  def name; "comment"; end

  def content
    Leptris::XML::FFI.leptris_comment_node_get_content(@c_ptr)
  end

  def content=(new_content)
    status = Leptris::XML::FFI.leptris_comment_node_set_content(@c_ptr, new_content.to_s)
    raise Leptris::XML::Error,
      Leptris::XML::FFI.leptris_status_string(status) unless status == Leptris::XML::FFI::LEPTRIS_OK
    new_content
  end
end
