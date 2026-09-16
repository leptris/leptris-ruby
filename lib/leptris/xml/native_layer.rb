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
    require "leptris/xml/native"
  end
rescue LoadError => e
  raise LoadError, <<~MSG
    leptris: the compiled native read layer is not available in
    this install (#{e.message}). It ships in platform gems; the
    ruby-platform variant does not carry it.
  MSG
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

  # Builder factories that return NativeNodes (#149): one C call
  # and a TypedData wrap — no FFI::Pointer, no wrap_fresh path.
  def native_create_element(name)
    Leptris::XML::NativeNode.create_element(self, name.to_s)
  end

  def native_create_text(content)
    Leptris::XML::NativeNode.create_text(self, content.to_s)
  end

  def native_root=(element)
    Leptris::XML::NativeNode.set_root(self, element)
    element
  end
end
