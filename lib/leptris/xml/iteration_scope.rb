# frozen_string_literal: true

require "ffi"

# The owning context for elements yielded by an Iterparse run —
# the lifetime and memoization authority that a Document is for
# parsed trees, scoped to one iteration:
#
# - `#c_ptr` carries the iterator handle and goes nil on `#free` —
#   the same signal `Node#ensure_alive!` reads, so using a held
#   element after the iterator frees RAISES UseAfterFreeError
#   instead of segfaulting (ruby#152).
# - `#wrapper_cache` gives wrapper identity within a yielded
#   subtree (children() twice returns the same wrappers).
# - `#version` advances per yield and on mutation — stale memos on
#   held wrappers invalidate as subtrees are released.
#
# `Node#document` answers nil for scope-owned elements (the
# documented iterparse contract) while the internal machinery
# engages — including the fast bare-name attribute path, which is
# what makes iterparse attribute reads match document-backed cost.
class Leptris::XML::IterationScope
  def initialize(iterator_handle)
    @c_ptr = iterator_handle
    @wrapper_cache = {}
    @version = 0
  end

  attr_reader :c_ptr, :wrapper_cache

  def version
    @version
  end

  def advance_version
    @version += 1
  end

  def readonly?
    false
  end

  # Called by the owning Iterparse when it frees the C iterator —
  # every wrapper it handed out fails liveness from here on.
  def mark_freed
    @c_ptr = nil
  end

  # Called before each yield: the previous subtree is released and
  # its pool memory recycled — a fresh element may land at a cached
  # address, so the identity cache and the memo version both reset.
  def new_subtree!
    @wrapper_cache = {}
    @version += 1
  end
end
