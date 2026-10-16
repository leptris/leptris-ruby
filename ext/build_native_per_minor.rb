# frozen_string_literal: true

# Builds the native read layer bundle for the CURRENT Ruby and
# installs it under its minor-versioned name
# (lib/leptris/xml/native_<major>_<minor>.bundle on darwin, .so on
# Linux).
#
# ruby#476: the ext's compiled-in RString layout changed in Ruby
# 3.2 — a bundle built by a newer minor reads garbage pointers and
# lengths under 3.1 (the parse segfaulted inside the engine's
# correctly-bounded NEON text counter). One bundle per supported
# minor therefore ships in the darwin/Linux platform gems — the
# same contract the Windows gems have had since #207/#227 — and
# native_layer picks by RUBY_VERSION at require, falling back to
# the FFI surface when the variant for the running minor is
# absent. A WRONG-ABI load is never attempted.
#
# The name is DOT-FREE: MRI derives a C extension's init symbol
# from the require feature's basename cut at the first dot, so
# native_3_1.bundle resolves Init_native_3_1 (exported by
# native.c).

require "rbconfig"
require "fileutils"

root = File.expand_path("..", __dir__)
ext_dir = File.join(root, "ext", "leptris", "native")
minor = RUBY_VERSION[/\A\d+\.\d+/]
minor_us = minor.tr(".", "_")
ext = RUBY_PLATFORM.include?("darwin") ? ".bundle" : ".so"

Dir.chdir(ext_dir) do
  # Force a clean compile on every invocation (stale objects from
  # a failed earlier attempt ship silent wrong-ABI builds).
  FileUtils.rm_f(Dir.glob("#{ext_dir}/native.{o,so,bundle}"))
  system(RbConfig.ruby, "extconf.rb") or abort "extconf failed under #{RUBY_VERSION}"
  # Link WITHOUT libruby (#1739): mkmf's Makefile rule records the
  # building ruby's libruby — for setup-ruby builds by absolute
  # hostedtoolcache path — in every LC_LOAD_DYLIB / DT_NEEDED, which
  # dlopen-fails on any other machine. Compile via the Makefile,
  # link exactly like rake compile's native branch: pure
  # dynamic_lookup, rb_* resolve from the loading interpreter.
  system("make native.o") or abort "make native.o failed under #{RUBY_VERSION}"
  cc = RbConfig::CONFIG["CC"]
  link =
    if ext == ".bundle"
      "#{cc} -dynamic -bundle -undefined dynamic_lookup " \
        "-mmacosx-version-min=#{ENV['MACOSX_DEPLOYMENT_TARGET'] || '11.0'} " \
        "-o native.bundle native.o"
    else
      "#{cc} -shared -fPIC -o native.so native.o"
    end
  system(link) or abort "native link failed under #{RUBY_VERSION}: #{link}"
  built = Dir.glob("native.{so,bundle}").first
  abort "native bundle not produced under #{RUBY_VERSION}" unless built

  # Linkage gate: no libruby reference, and (darwin) only
  # allowlisted load commands — enforced HERE so a violated bundle
  # never reaches packaging (the 1.9.36x trains shipped exactly
  # this shape, #1739).
  system(RbConfig.ruby, File.join(root, "ext", "check_bundle_linkage.rb"),
         File.expand_path(built)) or
    abort "linkage gate failed under #{RUBY_VERSION}"

  # Functional gate: dlopen the built bundle and resolve the
  # MINOR-SUFFIXED init symbol — only a real lookup proves
  # require "leptris/xml/native_<minor>" will resolve.
  begin
    require "fiddle"
    Fiddle.dlopen(File.expand_path(built))["Init_native_#{minor_us}"]
  rescue LoadError => e
    warn "fiddle unavailable under #{RUBY_VERSION} (#{e.message}) — skipping"
  rescue Fiddle::DLError => e
    abort "#{built} does not export Init_native_#{minor_us} — refusing to " \
          "install a bundle that would fail at require (#{e.message})"
  end

  dest = File.join(root, "lib", "leptris", "xml", "native_#{minor_us}#{ext}")
  FileUtils.cp(built, dest)
  puts "Installed native layer for Ruby #{minor} -> #{dest}"
end
