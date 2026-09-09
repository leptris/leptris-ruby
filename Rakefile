# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Pin for `rake compile` and the platform-gem builds. Keep in lockstep
# with .github/workflows/build.yml (which calls `rake compile`) and the
# CHANGELOG when libleptris releases.
LIBLEPTRIS_VERSION = "1.9.115"
# Vendored alongside libleptris for fn:normalize-unicode (TODO
# .restructure/20): built per platform with a RELOCATABLE @rpath
# install name, loaded by ffi.rb before libleptris so the
# dependent image resolves inside the gem.
UTF8PROC_VERSION = "2.11.0"


CMAKE_FLAGS = %w[
  -DCMAKE_BUILD_TYPE=Release
  -DLEPTRIS_BUILD_SHARED=ON
  -DLEPTRIS_BUILD_STATIC=OFF
  -DBUILD_TESTING=OFF
  -DLEPTRIS_BUILD_CLI=OFF
  -DLEPTRIS_BUILD_BENCHMARKS=OFF
  -DLEPTRIS_BUILD_MAN_PAGES=OFF
  -DLEPTRIS_ENABLE_UTF8PROC=OFF
  -DLEPTRIS_ENABLE_ICONV=OFF
].freeze

desc "Build libleptris #{LIBLEPTRIS_VERSION} (+ utf8proc) from release tarballs into lib/"
task :compile do
  version = ENV.fetch("LIBLEPTRIS_VERSION", LIBLEPTRIS_VERSION)
  build = File.expand_path("tmp/libleptris-#{version}", __dir__)
  rm_rf(build)
  mkdir_p(build)
  url = "https://api.github.com/repos/leptris/leptris/tarball/v#{version}"
  sh "curl -sL #{url} | tar xz -C #{build} --strip-components=1"

  # utf8proc: shared build only, @rpath install name, local prefix.
  u8_dir = File.expand_path("tmp/utf8proc-#{UTF8PROC_VERSION}", __dir__)
  u8_prefix = File.join(u8_dir, "prefix")
  rm_rf(u8_dir)
  mkdir_p(u8_dir)
  u8_url = "https://github.com/JuliaStrings/utf8proc/releases/download/v#{UTF8PROC_VERSION}/utf8proc-#{UTF8PROC_VERSION}.tar.gz"
  # The piped form is the shape the libleptris fetch already uses —
  # the -o file form produced a non-gzip artifact on the Windows
  # runners (tar child status 128).
  sh "curl -sL #{u8_url} | tar xz -C #{u8_dir} --strip-components=1"
  sh "cmake -B #{u8_dir}/build -S #{u8_dir} -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DUTF8PROC_ENABLE_TESTING=OFF"
  sh "cmake --build #{u8_dir}/build --config Release -j 4"
  sh "cmake --install #{u8_dir}/build --prefix #{u8_prefix}"

  # libleptris 1.9.18's xslt_functions.c:270 assigns LeptrisElement
  # to LeptrisNodeRef — GCC 14 (Alpine/musl) makes incompatible
  # pointer types an error by default and the musl platform gems
  # fail to build; clang toolchains only warn. Downgrade to warning
  # until the upstream fix (leptris/leptris#640).
  # No quoting: the flag carries no spaces, and single quotes are
  # literal on Windows shells (they broke the MSVC build).
  # GCC-family only — MSVC's cl rejects the flag outright (D8021).
  cflags = Gem.win_platform? ? "" : "-Wno-error=incompatible-pointer-types"
  sh "cmake -B #{build}/build -S #{build} " \
     "#{CMAKE_FLAGS.join(' ').sub('-DLEPTRIS_ENABLE_UTF8PROC=OFF', '-DLEPTRIS_ENABLE_UTF8PROC=ON')} " \
     "-DCMAKE_PREFIX_PATH=#{u8_prefix} #{cflags.empty? ? '' : "-DCMAKE_C_FLAGS=#{cflags}"}"
  sh "cmake --build #{build}/build --config Release -j 4"
  # Windows names the shared library leptris.dll (no "lib" prefix);
  # vendoring under the uniform libleptris.* name keeps the FFI
  # search order simple. libleptris >= 1.3.0 renames the DLL to
  # libleptris.dll on Windows too (leptris/leptris#507, issue
  # TODO.concurrency/05) — accept both names.
  lib = Dir.glob("#{build}/build/**/libleptris.{dylib,so,dll}").first ||
        Dir.glob("#{build}/build/**/leptris.dll").first
  raise "libleptris shared library not found after build" unless lib
  ext = File.extname(lib)
  cp(lib, "lib/libleptris#{ext}")
  # The SONAME file is what @rpath references — .3.dylib on
  # macOS, .so.3 on Linux (cmake installs the symlink chain;
  # copying the symlink copies the target), plain .dll on
  # Windows.
  u8_lib = Dir.glob("#{u8_prefix}/lib/libutf8proc.3.dylib").first ||
           Dir.glob("#{u8_prefix}/lib/libutf8proc.so.3").first ||
           Dir.glob("#{u8_prefix}/lib/libutf8proc.so").first ||
           Dir.glob("#{u8_prefix}/{lib,bin}/utf8proc.dll").first
  raise "utf8proc shared library not found after build" unless u8_lib
  cp(u8_lib, "lib/#{File.basename(u8_lib)}")
  puts "Vendored #{File.basename(lib)} + #{File.basename(u8_lib)} into lib/"
end

task spec: :compile unless ENV.key?("LEPTRIS_LIB_PATH")

task default: :spec

# Lockstep drift detector (ADR 0001): ffi.rb mirrors the public
# header, so attached == exported must hold on the vendored library.
# Run after `rake compile` and before any lockstep release.
namespace :audit do
  desc "Fail when ffi.rb attachments and library exports drift"
  task :symbols do
    # nm cannot read MSVC PE export tables (every symbol reports as
    # unexported -> guaranteed false drift), so Windows skips: the
    # darwin/linux CI legs enforce the mirror — any one platform's
    # build of the same C surface suffices.
    if Gem.win_platform?
      puts "audit:symbols: skipped on Windows (PE export tables); " \
           "darwin/linux legs enforce the mirror"
      next
    end
    # Probe nm without a shell: the multi-arg system() execs
    # directly, so there is no which/redirect syntax to be
    # platform-hostile. File::NULL is NUL where it must be; a
    # missing binary is falsy either way (ENOENT rescue belts the
    # older spawn behavior).
    unless nm_available?
      puts "audit:symbols: skipped (nm unavailable on this platform)"
      next
    end
    lib = Dir.glob("lib/libleptris.{dylib,so,dll}").first
    unless lib
      abort "audit:symbols: vendored library not found — run rake compile"
    end
    exported = `nm -gU #{lib}`
      .lines.map { |l| l.split[2] }.compact
      .map { |n| n.sub(/\A_/, "") }
      .select { |n| n.start_with?("leptris_") }
      .map { |n| n.sub(/\Aleptris_/, "") }.sort
    attached = File.read("lib/leptris/xml/ffi.rb")
      .scan(/attach_function :leptris_([a-z_0-9]+)/).flatten.sort
    unattached = exported - attached
    unexported = attached - exported
    unless unattached.empty?
      puts "exported but NOT attached (upstream surface drift):"
      unattached.each { |s| puts "  leptris_#{s}" }
    end
    unless unexported.empty?
      puts "attached but NOT exported (stale attachment):"
      unexported.each { |s| puts "  leptris_#{s}" }
    end
    if unattached.empty? && unexported.empty?
      puts "audit:symbols: #{attached.length}/#{exported.length} symbols in lockstep"
    else
      abort "audit:symbols: drift detected"
    end
  end

  # @api private
  def nm_available?
    system("nm", "--version", out: File::NULL, err: File::NULL)
  rescue Errno::ENOENT
    false
  end
end

require "rubygems/package_task"

desc "Build the pure-Ruby gem"
task "gem:native:any" do
  sh "rake platform:any gem"
end

desc "Define the gem task to build the pure-Ruby gem"
task "platform:any" do
  spec = Gem::Specification::load("leptris.gemspec").dup
  task = Gem::PackageTask.new(spec)
  task.define
end

platforms = [
  "x64-mingw32",
  "x64-mingw-ucrt",
  "aarch64-mingw-ucrt",
  "x86_64-linux",
  "x86_64-linux-musl",
  "aarch64-linux",
  "aarch64-linux-musl",
  "x86_64-darwin",
  "arm64-darwin",
]

platforms.each do |platform|
  desc "Build pre-compiled gem for the #{platform} platform"
  task "gem:native:#{platform}" do
    sh "rake compile platform:#{platform} gem"
  end

  desc "Define the gem task to build on the #{platform} platform (binary gem)"
  task "platform:#{platform}" do
    spec = Gem::Specification::load("leptris.gemspec").dup
    spec.platform = Gem::Platform.new(platform)
    spec.files += Dir.glob("lib/libleptris.{dll,so,dylib}")
    spec.files += Dir.glob("lib/{libutf8proc.3.dylib,libutf8proc.so.3,libutf8proc.so,utf8proc.dll}")
    task = Gem::PackageTask.new(spec)
    task.define
  end
end

require "rake/clean"

CLOBBER.include("pkg")
CLEAN.include("tmp",
              "lib/libleptris.dll",
              "lib/libleptris.dylib",
              "lib/libleptris.so",
              "lib/libutf8proc.3.dylib",
              "lib/libutf8proc.so.3",
              "lib/libutf8proc.so",
              "lib/utf8proc.dll")
