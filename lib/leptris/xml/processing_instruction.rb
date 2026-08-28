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

  # Since libleptris 1.9.9 (#612) parse-created document-level PIs
  # carry document linkage — the setters work on them like on any
  # tree-level PI.
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

  # Document-level PIs have no tree parent for leptris_node_unlink
  # — route through the document-level removal (libleptris 1.9.9,
  # #612), identity-matched by index so the right same-target PI
  # comes out.
  def unlink
    ensure_writable!
    rc = Leptris::XML::FFI.leptris_node_unlink(@c_ptr)
    if rc == Leptris::XML::FFI::LEPTRIS_ERROR_NOT_FOUND
      index = document_pi_index
      if index.negative?
        raise Leptris::XML::Error,
          "PI not found in its document — already removed?"
      end
      removed = @document.remove_pi(index)
      unless removed && removed.c_ptr == @c_ptr
        raise Leptris::XML::Error, "document-level PI removal missed"
      end
      @parent = nil
      return self
    end
    Leptris::XML::FFI.check_status(rc)
    @parent = nil
    self
  end

  private

  # This PI's 0-based index among the document's PIs (document
  # order — the same enumeration leptris_document_remove_pi uses).
  def document_pi_index
    pi_index = -1
    @document.children.each do |child|
      pi_index += 1 if child.pi?
      return pi_index if child.c_ptr == @c_ptr
    end
    -1
  end
end
