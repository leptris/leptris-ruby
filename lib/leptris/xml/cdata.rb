# frozen_string_literal: true

class Leptris::XML::CDATA < Leptris::XML::Text
  def name; "#cdata-section"; end

  def content
    # Frozen-tree fast path (leptris-ruby#336): frozen leaves are
    # COW — never written in place — so a populated memo is eternal;
    # skips the memo_hit?/ensure_alive!/version dispatch chain.
    # Elements must NOT take this path: a frozen parent's child slot
    # is re-pointed on child COW, so subtree content can change.
    return @content if @content && @document && @document.frozen_tree?

    return @content if memo_hit?(@content_version)
    ensure_alive!
    result = if @addr_reads_fast
               Leptris::XML::Native.fast_cdata_content(@c_address)
             else
               Leptris::XML::FFI.leptris_cdata_node_get_content(c_ptr)
             end
    if @document
      @content = result
      @content_version = @document.version
    end
    result
  end

  def content=(new_content)
    ensure_writable!
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_cdata_node_set_content(c_ptr, new_content.to_s))
    new_content
  end
end
