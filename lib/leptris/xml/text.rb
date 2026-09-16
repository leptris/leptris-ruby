# frozen_string_literal: true

class Leptris::XML::Text < Leptris::XML::Node
  def name; "text"; end

  def content
    return @content if memo_hit?(@content_version)
    ensure_alive!
    result = if @addr_reads_fast
               Leptris::XML::Native.fast_text_content(@c_address)
             else
               Leptris::XML::FFI.leptris_text_node_get_content(c_ptr)
             end
    if @document
      @content = result
      @content_version = @document.version
    end
    result
  end

  def content=(new_content)
    if @native_fast
      Leptris::XML::Native.set_binding_text(
        @document, @c_address, new_content.to_s)
      return new_content
    end
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_text_node_set_content(c_ptr, new_content.to_s))
    new_content
  end
end
