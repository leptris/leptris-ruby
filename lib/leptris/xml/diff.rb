# frozen_string_literal: true

require "ffi"

module Leptris::XML::Diff
  module_function

  # Structural tree diff (libleptris >= 1.9.127): equal subtrees
  # prune in O(1) via the #869 content-defined Merkle digest;
  # diverging regions align via an LCS on child digests, then
  # same-named elements recurse.
  #
  #     script = Leptris::XML::Diff.diff(doc_a, doc_b)
  #     script.ops            # => 0 when structurally identical
  #     script.serialize      # => line-per-op text form
  #     script.each_op { |o| ... }  # type/path/name/before/after
  #
  def diff(a, b, ignore_ws: false)
    raw = Leptris::XML::FFI.leptris_diff(
      a.c_ptr, b.c_ptr,
      ignore_ws ? 1 : 0, nil)
    return nil if raw.null?
    Script.new(Script::Handle.new(raw))
  end

  # The boolean fast path canon-style consumers want: are the two
  # trees structurally identical? Zero ops == identical — the
  # digest pruning makes the common equal case O(1) per subtree.
  def identical?(a, b, ignore_ws: false)
    script = diff(a, b, ignore_ws: ignore_ws)
    return false if script.nil?
    script.ops.zero?
  end

  # One op in the edit script. type is one of :insert, :delete,
  # :update_text, :update_attr; path is root-relative ("/r/i[2]");
  # name is the attribute name (update_attr) or element name
  # (insert/delete); before/after carry the payloads ("" when a
  # side is absent).
  class Op
    TYPES = { 1 => :insert, 2 => :delete,
              3 => :update_text, 4 => :update_attr }.freeze

    attr_reader :type, :path, :name, :before, :after

    def initialize(type, path, name, before, after)
      @type = type
      @path = path
      @name = name
      @before = before
      @after = after
    end
  end

  class Script
    class Handle < ::FFI::AutoPointer
      def self.release(ptr)
        Leptris::XML::FFI.leptris_diff_free(ptr)
      end
    end

    def initialize(handle)
      @handle = handle
    end

    # Number of ops (0 == structurally identical trees).
    def ops
      Leptris::XML::FFI.leptris_diff_op_count(@handle)
    end

    def each_op
      return enum_for(:each_op) unless block_given?
      n = ops
      i = 0
      while i < n
        yield Op.new(
          Op::TYPES[Leptris::XML::FFI.leptris_diff_op_type(
            @handle, i)] || :unknown,
          str(Leptris::XML::FFI.leptris_diff_op_path(@handle, i)),
          str(Leptris::XML::FFI.leptris_diff_op_name(@handle, i)),
          str(Leptris::XML::FFI.leptris_diff_op_before(@handle, i)),
          str(Leptris::XML::FFI.leptris_diff_op_after(@handle, i)))
        i += 1
      end
    end

    # Line-per-op text form:
    #   '- <path> @<attr> "<before>" -> "<after>"'  (UPDATE_ATTR)
    #   '~ <path> "<before>" -> "<after>"'          (UPDATE_TEXT)
    #   '+ <path> <<name>>'                          (INSERT)
    #   'x <path> <<name>>'                          (DELETE)
    def serialize
      Leptris::XML::FFI.read_owned_string(
        Leptris::XML::FFI.leptris_diff_serialize(@handle))
    end

    private

    # FFI :string returns are already Ruby Strings (nil for NULL).
    def str(s)
      s.nil? ? "" : s
    end
  end
end
