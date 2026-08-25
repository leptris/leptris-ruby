# frozen_string_literal: true

class Leptris::XML::Comment < Leptris::XML::Node
  def name; "comment"; end

  def content
    return @content if readonly_cached?(:@content)
    ensure_alive!
    Leptris::XML::FFI.leptris_comment_node_get_content(@c_ptr).tap do |text|
      @content = text if @document&.readonly?
    end
  end

  def content=(new_content)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_comment_node_set_content(@c_ptr, new_content.to_s))
    new_content
  end
end
