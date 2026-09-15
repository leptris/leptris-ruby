# frozen_string_literal: true

# Builds the native read layer DLL for the CURRENT Ruby and
# installs it under its minor-versioned name
# (lib/leptris/xml/native-<major.minor>.so).
#
# #207/#227: a PE DLL cannot resolve Ruby imports lazily — it
# must bind the build Ruby's x64-ucrt-rubyNNN.dll. One DLL per
# supported minor therefore ships in the Windows platform gems,
# and native_layer picks by RUBY_VERSION at require.
#
# Standalone by design: the release workflow runs this under each
# Ruby minor (3.3/3.4/4.0) with no bundler context.

require "rbconfig"
require "fileutils"

root = File.expand_path("..", __dir__)
ext_dir = File.join(root, "ext", "leptris", "native")
minor = RUBY_VERSION[/\A\d+\.\d+/]

Dir.chdir(ext_dir) do
  system(RbConfig.ruby, "extconf.rb") or abort "extconf failed under #{RUBY_VERSION}"
  # mkmf's link binds the CURRENT Ruby's runtime DLL — exactly
  # what the versioned naming is for.
  success = system("make")
  abort "make failed under #{RUBY_VERSION}" unless success
  so = Dir.glob("native.{so,dll}").first
  abort "native bundle not produced under #{RUBY_VERSION}" unless so
  dest = File.join(root, "lib", "leptris", "xml", "native-#{minor}.so")
  # The artifact must reference only this minor's Ruby DLL.
  imported = `strings #{so} 2>/dev/null`[/[a-z0-9-]*ruby\d{3,}\.dll/i]
  if imported && !imported.include?("ruby#{minor.delete('.')}")
    abort "#{so} imports #{imported} but was built under #{RUBY_VERSION} — refuse to mis-name it"
  end
  FileUtils.cp(so, dest)
  puts "Installed native layer for Ruby #{minor} -> #{dest} (#{imported || 'no ruby dll string found'})"
end
