# frozen_string_literal: true

require "open3"
require "rbconfig"

# TODO.final/04: the shipped-artifact gates. Required by
# Rakefile's audit:artifacts task and by the negative-proof specs
# (spec/audit_codesign_spec.rb). Not shipped in the gem — this is
# packaging/CI tooling.
module AuditArtifacts
  module_function

  # Every vendored macOS artifact the gem ships (the darwin
  # packaging set, wherever it currently lives).
  def darwin_artifacts
    %w[
      lib/libleptris.dylib
      lib/libutf8proc.3.dylib
      lib/leptris/xml/native.bundle
    ] + Dir.glob("lib/leptris/vendor/*-darwin/**/*.{dylib,bundle}")
  end

  # (a) tamper gate: --strict verifies the embedded signature
  # covers the CURRENT bytes; a copy/strip/recompress invalidates
  # it and this fails instead of a user machine's dlopen.
  def signature_ok?(path)
    system("codesign", "--verify", "--strict", path,
           out: File::NULL, err: File::NULL)
  end

  def codesign_available?
    # codesign has no --version; `which`-style probe via -h
    # (exit 1 with usage output still proves the binary exists —
    # ENOENT returns nil).
    !system("codesign", "-h", out: File::NULL, err: File::NULL).nil?
  end

  # (b) artifact/version sync: the vendored library's own
  # leptris_version() must equal the Rakefile's engine pin — a
  # half-bumped lockstep state can no longer package. Runs the
  # vendored library in an isolated interpreter (no gem load).
  def vendored_version(lib, lib_dir)
    env = { "LEPTRIS_LIB_PATH" => lib,
            "DYLD_FALLBACK_LIBRARY_PATH" => lib_dir }
    out, status = Open3.capture2e(env, RbConfig.ruby,
                                  "-rffi", "-e",
                                  'require "ffi"; ' \
                                  'module V; extend FFI::Library; ' \
                                  'ffi_lib ENV["LEPTRIS_LIB_PATH"]; ' \
                                  'attach_function :v, :leptris_version, [], :string; end; ' \
                                  'print V.v')
    status.success? ? out.strip : nil
  end

  def version_synced?(lib, lib_dir, pinned)
    vendored = vendored_version(lib, lib_dir)
    !vendored.nil? && vendored == pinned
  end
end
