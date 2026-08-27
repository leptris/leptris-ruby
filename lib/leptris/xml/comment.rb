# frozen_string_literal: true

class Leptris::XML::Comment < Leptris::XML::Node
  def name; "comment"; end

  def content
    return @content if memo_hit?(@content_version)
    ensure_alive!
    result = Leptris::XML::FFI.leptris_comment_node_get_content(@c_ptr)
    if @document
      @content = result
      @content_version = @document.version
    end
    result
  end

  def content=(new_content)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_comment_node_set_content(@c_ptr, new_content.to_s))
    new_content
  end
end
