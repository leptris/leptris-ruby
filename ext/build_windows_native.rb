# frozen_string_literal: true

# Builds the native read layer DLL for the CURRENT Ruby and
# installs it under its minor-versioned name
# (lib/leptris/xml/native_<major>_<minor>.so).
#
# #207/#227: a PE DLL cannot resolve Ruby imports lazily — it
# must bind the build Ruby's x64-ucrt-rubyNNN.dll. One DLL per
# supported minor therefore ships in the Windows platform gems,
# and native_layer picks by RUBY_VERSION at require.
#
# The name is DOT-FREE: MRI derives a C extension's init symbol
# from the require feature's basename cut at the first dot, so
# native_3_3.so resolves Init_native_3_3 (a valid C symbol,
# exported by native.c) — a dotted native-3.3.so would make Ruby
# look for "Init_native-3", which cannot exist.

require "rbconfig"
require "fileutils"

root = File.expand_path("..", __dir__)
ext_dir = File.join(root, "ext", "leptris", "native")
minor = RUBY_VERSION[/\A\d+\.\d+/]
minor_us = minor.tr(".", "_")
INIT_PREFIX = "Init_native_"

Dir.chdir(ext_dir) do
  # aarch64-ucrt 1.9.221.0 shipped a DLL exporting only Init_native
  # because make reused a stale native.obj from a failed earlier
  # attempt (the log shows "creating Makefile -> linking" with no
  # compile). Force a clean compile on every invocation.
  FileUtils.rm_f(Dir.glob("#{ext_dir}/native.{o,obj,so,dll}"))
  FileUtils.rm_f("#{ext_dir}/leptris/xml/native.so")
  system(RbConfig.ruby, "extconf.rb") or abort "extconf failed under #{RUBY_VERSION}"
  # mkmf's link binds the CURRENT Ruby's runtime DLL — exactly
  # what the versioned naming is for.
  success = system("make")
  abort "make failed under #{RUBY_VERSION}" unless success
  so = Dir.glob("native.{so,dll}").first
  abort "native bundle not produced under #{RUBY_VERSION}" unless so
  # Functional export gate: dlopen the built DLL and resolve the
  # MINOR-SUFFIXED init symbol. A PE DLL can carry the symbol in its
  # string table while exporting only mkmf's Init_native (the arm64
  # toolchain ignores our .def when its own wins the link) — only a
  # real lookup proves native_<minor>.so will load.
  #
  # Ruby 4.0 moved fiddle out of the default gems (bundled_gems
  # intercepts the require → LoadError when it's not in the
  # Gemfile), so the gate is conditional there: skip loudly — the
  # release workflow's strings gate still hard-verifies the
  # export, and native.c pins the symbols with dllexport at the
  # source level.
  begin
    require "fiddle"
  rescue LoadError => e
    warn "fiddle unavailable under #{RUBY_VERSION} (#{e.message}) — " \
         "skipping the functional export gate; the release workflow's " \
         "strings gate still applies"
  end
  if defined?(Fiddle)
    begin
      Fiddle.dlopen(File.expand_path(so))[INIT_PREFIX + minor_us]
    rescue Fiddle::DLError => e
      abort "#{so} does not export #{INIT_PREFIX + minor_us} — refusing to " \
            "install a DLL that would 127 at require (#{e.message})"
    end
  end
  dest = File.join(root, "lib", "leptris", "xml", "native_#{minor_us}.so")
  # The artifact must reference only this minor's Ruby DLL.
  imported = `strings #{so} 2>/dev/null`[/[a-z0-9-]*ruby\d{3,}\.dll/i]
  if imported && !imported.include?("ruby#{minor.delete('.')}")
    abort "#{so} imports #{imported} but was built under #{RUBY_VERSION} — refuse to mis-name it"
  end
  FileUtils.cp(so, dest)
  puts "Installed native layer for Ruby #{minor} -> #{dest} (#{imported || 'no ruby dll string found'})"
end
