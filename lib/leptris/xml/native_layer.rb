# frozen_string_literal: true

# Opt-in native read layer (TODO.restructure/21 round 2, #185):
# TypedData node wrappers with C-bound hot reads and bulk children
# construction — measured 6.2x on raw walks. Load explicitly:
#
#     require "leptris/xml/native"
#     root = doc.native_node
#     root.children.each { |c| c.name }
#
# Identity is shared with the binding through the per-document
# wrapper cache, so native and binding views of one document
# interoperate. The default require path never loads this file;
# installs without the compiled bundle (ruby-platform gem) raise
# a clear LoadError from the require.

require "ffi" unless defined?(::FFI::Library)

begin
  # The compiled bundle. A sanctioned require exception: a
  # .bundle/.so cannot go through autoload. Missing in installs
  # that do not vendor it (ruby-platform gem). Windows names the
  # artifact per Ruby minor, DOT-FREE (#207/#227): a PE DLL must
  # bind its build Ruby's runtime (one DLL per minor), and MRI
  # derives the init symbol from the basename cut at the first
  # dot — native_3_3.so resolves Init_native_3_3.
  if Gem.win_platform?
    require "leptris/xml/native_#{RUBY_VERSION[/\A\d+\.\d+/].tr('.', '_')}"
  else
    # Per-minor bundle FIRST (ruby#476): the ext's compiled-in
    # RString layout changed in 3.2 — a bundle built by a newer
    # minor reads garbage pointers/lengths under 3.1 (the parse
    # segfaulted inside the engine's (correctly bounded) text
    # counter). Platform gems ship one bundle per minor, MRI
    # derives Init_native_<minor> from the basename cut at the
    # first dot, and a missing variant falls through to FFI below
    # — a WRONG-ABI load must never be attempted.
    minor = RUBY_VERSION[/\A\d+\.\d+/].tr('.', '_')
    ext = RUBY_PLATFORM.include?('darwin') ? '.bundle' : '.so'
    per_minor = File.expand_path("native_#{minor}#{ext}", __dir__)
    # No unversioned fallback on purpose: a bundle built by any
    # other minor is a wrong-ABI load (the 3.1 segfault class).
    # Absent variant -> LoadError -> leptris.rb falls back to the
    # FFI surface with a warning.
    raise LoadError,
          "leptris: no native_#{minor} bundle in this install " \
          "(per-minor native layer; ruby-platform gems compile " \
          "at install)" unless File.exist?(per_minor)
    # #1623: the bundle beside this file must carry a valid
    # signature before dyld maps it — pre-verify and re-stamp.
    Leptris.resign_bundle_if_needed(per_minor)
    require "leptris/xml/native_#{minor}"
  end
rescue LoadError => e
  raise LoadError, <<~MSG
    leptris: the compiled native read layer is not available in
    this install (#{e.message}). It ships in platform gems; the
    ruby-platform variant does not carry it.
  MSG
end

# Certificate module for the bulk XPath rows face: an Array extended
# with this carries ONLY born-primed registered-klass identity natives
# (xpath_result_rows_bulk answered with a consumer context+adapter, so
# @native is the node itself and @context/@adapter are already set).
# Consumers with a per-row wrap in their result loop can key a fast
# path on it (moxml's NodeSet#each); one object per native address
# remains the binding's native-cache contract (#529) either way.
module Leptris::XML::BulkIdentityRows
  def bulk_identity_rows?
    true
  end
end

module Leptris::XML::Native
  # FFI.libleptris_candidates is the single source of truth — the
  # native layer MUST dlsym the exact image the FFI layer loaded,
  # or two library instances split per-document state.
  def self.lib_candidates
    Leptris::XML::FFI.libleptris_candidates
  end
end

# TODO.perf/01: accelerate the DEFAULT binding classes while the
# bundle is loaded (name/content/prefix/[] hot reads).
Leptris::XML::NATIVE_FAST = true

candidates = Leptris::XML::Native.lib_candidates
resolved = candidates.any? do |path|
  begin
    Leptris::XML::NativeNode.resolve!(path)
    true
  rescue RuntimeError
    false
  end
end
raise LoadError,
  "leptris: native layer loaded but libleptris could not be " \
  "resolved from #{candidates.inspect}" unless resolved

class Leptris::XML::Document
  # Separate identity cache for NativeNodes so binding Node.wrap
  # and the native layer never overwrite each other.
  def native_cache
    @native_cache ||= {}
  end

  def native_node
    r = root or raise Leptris::XML::Error, "document has no root element"
    Leptris::XML::NativeNode.from(self, r.c_ptr)
  end

  # #340: per-kind wrapper-klass registration for THIS document.
  # map is an Array of classes/nil indexed by node kind (element,
  # text, comment, cdata, pi) — the same shape
  # NativeNode.install_child_klasses uses. Once registered, the C
  # walk cache (trav/visit) and the create faces mint those
  # klasses directly (TypedData path, native-cache identity), so
  # consumers receive their own contract-carrying nodes straight
  # from the crossing with no re-wrap.
  def register_wrapper_klasses(map)
    Leptris::XML::Native.register_doc_klasses(self, map)
  end

  # leptris-ruby#529: the whole XPath node-set result as an Array of
  # NativeNodes in ONE C call — the iterate-every-row lane's bulk
  # face. Rows mint through the registered wrapper klasses (#340)
  # with native-cache identity; synthetic attribute/sequence rows
  # keep the ResultAttr/ResultText wrappers the eager path minted.
  # Takes the raw result pointer eval_ptrs returned and CONSUMES it
  # (nodesets free the handle in C); a non-nodeset result answers
  # nil and leaves the pointer with the caller — route it through
  # Searchable.wrap_xpath_result for the scalar faces.
  # Optional (context, adapter): when the consumer passes its
  # contract state, every registered-klass row is born primed and an
  # all-native result extends with BulkIdentityRows — the consumer's
  # per-row wrap prime disappears from the iterate-every-result lane.
  def xpath_result_rows_bulk(result_ptr, mx_context = nil, mx_adapter = nil)
    Leptris::XML::Native.xpath_result_rows_bulk(
      self, result_ptr.respond_to?(:address) ? result_ptr.address
                                             : result_ptr,
      mx_context, mx_adapter)
  end

  # Builder factories that return NativeNodes (#149): one C call
  # and a TypedData wrap — no FFI::Pointer, no wrap_fresh path.
  # (context, adapter) pre-writes the consumer's contract ivars in
  # C — the mint returns a node that already answers them, and the
  # consumer's Ruby prime pass disappears from the build path.
  # Older compiled exts take two args; pass through only when given.
  def native_create_element(name, mx_context = nil, mx_adapter = nil)
    if mx_context.nil?
      Leptris::XML::NativeNode.create_element(self, name.to_s)
    else
      Leptris::XML::NativeNode.create_element(self, name.to_s,
                                              mx_context, mx_adapter)
    end
  end

  def native_create_text(content)
    Leptris::XML::NativeNode.create_text(self, content.to_s)
  end

  def native_root=(element)
    Leptris::XML::NativeNode.set_root(self, element)
    element
  end
end
