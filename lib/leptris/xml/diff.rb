# frozen_string_literal: true

require "ffi"

# Tree diff between two documents (libleptris >= 1.9.126):
# equal subtrees prune in O(1) via the #869 content-defined Merkle
# digest; diverging regions align through an LCS on child digests,
# then same-named elements recurse. Attribute add/remove are
# UPDATE_ATTR ops with an empty side.
#
#     diff = Leptris::XML.diff(before_doc, after_doc)
#     diff.ops    # => [{type: :update_text, name: "price",
#                    #      path: "/r/item[2]/price", before: "3", after: "4"}, ...]
#     diff.to_s   # => serialized op list
#     Leptris::XML.diff(a, b, ignore_ws: true)  # ws-only text absent
#
class Leptris::XML::Diff
  class Handle < ::FFI::AutoPointer
    def self.release(ptr)
      Leptris::XML::FFI.leptris_diff_free(ptr)
    end
  end

  OP_TYPES = {
    1 => :insert,
    2 => :delete,
    3 => :update_text,
    4 => :update_attr,
  }.freeze
  private_constant :OP_TYPES

  def self.compute(document_a, document_b, ignore_ws: false)
    flags = ignore_ws ? 1 : 0
    raw = Leptris::XML::FFI.leptris_diff(
      document_a.c_ptr, document_b.c_ptr, flags, nil)
    if raw.null?
      raise Leptris::XML::Error,
        "leptris_diff failed: #{Leptris::XML::FFI.leptris_last_error}"
    end
    new(Handle.new(raw))
  end

  def initialize(handle)
    @handle = handle
  end

  # The op list in document order: {type:, name:, path:, before:,
  # after:} — paths are root-relative ("/r/i[2]"); before/after
  # carry payloads (attribute values / text) where the op has them.
  def ops
    count = Leptris::XML::FFI.leptris_diff_op_count(@handle)
    Array.new(count) do |i|
      {
        type: OP_TYPES[Leptris::XML::FFI.leptris_diff_op_type(@handle, i)],
        name: Leptris::XML::FFI.leptris_diff_op_name(@handle, i),
        path: Leptris::XML::FFI.leptris_diff_op_path(@handle, i),
        before: Leptris::XML::FFI.leptris_diff_op_before(@handle, i),
        after: Leptris::XML::FFI.leptris_diff_op_after(@handle, i),
      }
    end
  end

  def to_s
    str_ptr = Leptris::XML::FFI.leptris_diff_serialize(@handle)
    Leptris::XML::FFI.read_owned_string(str_ptr)
  end
end
