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

begin
  # The compiled bundle (feature "leptris/xml/native" resolves
  # native.bundle). A sanctioned require exception: a .bundle
  # cannot go through autoload. Missing in installs that do not
  # vendor it (ruby-platform gem).
  require "leptris/xml/native"
rescue LoadError => e
  raise LoadError, <<~MSG
    leptris: the compiled native read layer is not available in
    this install (#{e.message}). It ships in platform gems; the
    ruby-platform variant does not carry it.
  MSG
end

module Leptris::XML::Native
  LIB_CANDIDATES = [
    ENV["LEPTRIS_LIB_PATH"],
    File.expand_path("../../libleptris.dylib", __dir__),
    File.expand_path("../../libleptris.so", __dir__),
    File.expand_path("../../libleptris.dll", __dir__),
    "libleptris",
  ].compact.freeze
end

candidates = Leptris::XML::Native::LIB_CANDIDATES
resolved = candidates.any? do |path|
  resolved = Leptris::XML::Native::LIB_CANDIDATES.any? do |path|
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
end

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
