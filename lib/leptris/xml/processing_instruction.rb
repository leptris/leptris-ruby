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

  # Parse-created document-level PIs carry no document linkage in
  # libleptris (leptris-ruby#92): the C setters reject them with
  # INVALID_ARG while tree-level and Document#add_pi PIs mutate
  # fine. Map that failure to the contract instead of a bare
  # "Invalid argument".
  READ_ONLY_NATIVE =
    "this PI is a parse-created document-level PI — its node has " \
    "no document linkage in libleptris, so target/data cannot be " \
    "written and it cannot be unlinked (leptris-ruby#92); " \
    "tree-level and Document#add_pi PIs are mutable"

  def target=(new_target)
    ensure_writable!
    rc = Leptris::XML::FFI.leptris_pi_node_set_target(
      @c_ptr, new_target.to_s)
    raise Leptris::XML::Error, READ_ONLY_NATIVE if
      rc == Leptris::XML::FFI::LEPTRIS_ERROR_INVALID_ARG
    Leptris::XML::FFI.check_status(rc)
    new_target
  end

  def data=(new_data)
    ensure_writable!
    rc = Leptris::XML::FFI.leptris_pi_node_set_data(
      @c_ptr, new_data.to_s)
    raise Leptris::XML::Error, READ_ONLY_NATIVE if
      rc == Leptris::XML::FFI::LEPTRIS_ERROR_INVALID_ARG
    Leptris::XML::FFI.check_status(rc)
    new_data
  end
end
