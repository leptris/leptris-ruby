# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Pin for `rake compile` and the platform-gem builds. Keep in lockstep
# with .github/workflows/build.yml (which calls `rake compile`) and the
# CHANGELOG when libleptris releases.
LIBLEPTRIS_VERSION = "1.9.188"
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

require "tmpdir"

desc "Build libleptris #{LIBLEPTRIS_VERSION} (+ utf8proc) from release tarballs into lib/"
task :compile do
  # GitHub tarball downloads intermittently return a non-gzip body
  # (rate-limit/redirect HTML) — the piped curl|tar form then fails
  # with "not in gzip format" and takes the leg down. Download to a
  # file with retries, validate the gzip magic, extract from the
  # file.
  # Whole-cycle retry: a truncated body can still start with the
  # gzip magic (Windows runners) and only fail at tar EOF — refetch
  # on any failure in the chain rather than trusting curl's exit
  # code alone.
  fetch_tarball = lambda do |url, dest_dir|
    attempts = 0
    begin
      attempts += 1
      tgz = File.join(Dir.tmpdir, "leptris-#{Time.now.to_i}-#{rand(1e9)}.tgz")
      begin
        sh "curl -sfL --retry 4 --retry-delay 2 --retry-all-errors -o #{tgz} #{url}"
        magic = File.binread(tgz, 2)
        unless magic.bytes == [0x1f, 0x8b]
          raise "downloaded #{url} is not gzip (got #{magic.bytes.inspect})"
        end
        # GNU tar (Git-bundled, Windows) parses D:/... as a
        # REMOTE host spec ("Cannot connect to D:") — the piped
        # form never had a file argument, so this only surfaces
        # with -o. --force-local is GNU tar; bsdtar (macOS) and
        # plain GNU tar (linux) don't need it but tolerate being
        # skipped.
        local_flag = Gem.win_platform? ? " --force-local" : ""
        sh "tar#{local_flag} -xzf #{tgz} -C #{dest_dir} --strip-components=1"
      ensure
        File.delete(tgz) if File.exist?(tgz)
      end
    rescue StandardError => e
      raise if attempts >= 3
      warn "tarball fetch attempt #{attempts} failed (#{e.message}); retrying"
      retry
    end
  end

  version = ENV.fetch("LIBLEPTRIS_VERSION", LIBLEPTRIS_VERSION)
  build = File.expand_path("tmp/libleptris-#{version}", __dir__)
  rm_rf(build)
  mkdir_p(build)
  fetch_tarball.call(
    "https://api.github.com/repos/leptris/leptris/tarball/v#{version}", build)

  # utf8proc: shared build only, @rpath install name, local prefix.
  u8_dir = File.expand_path("tmp/utf8proc-#{UTF8PROC_VERSION}", __dir__)
  u8_prefix = File.join(u8_dir, "prefix")
  rm_rf(u8_dir)
  mkdir_p(u8_dir)
  fetch_tarball.call(
    "https://github.com/JuliaStrings/utf8proc/releases/download/v#{UTF8PROC_VERSION}/utf8proc-#{UTF8PROC_VERSION}.tar.gz",
    u8_dir)
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
  cmake_base =
    "#{CMAKE_FLAGS.join(' ').sub('-DLEPTRIS_ENABLE_UTF8PROC=OFF', '-DLEPTRIS_ENABLE_UTF8PROC=ON')} " \
    "-DCMAKE_PREFIX_PATH=#{u8_prefix} #{cflags.empty? ? '' : "-DCMAKE_C_FLAGS=#{cflags}"}"

  # Two-stage PGO (engine CMake: LEPTRIS_ENABLE_PGO GENERATE/USE;
  # measured ~20% CPU on the DOM parse path, v1.9.188 worktree A/B,
  # every PGO round beating every baseline round). Train via the CLI
  # over the tarball's XML corpus. Windows keeps the plain build —
  # MSVC PGO is inherently LTCG and these gems link the DLL as-is.
  # LEPTRIS_PGO=0 escapes to the single-stage build.
  pgo = ENV["LEPTRIS_PGO"] != "0" && !Gem.win_platform?
  if pgo
    # _GNU_SOURCE for the TRAIN build only: the CLI (the trainer, not
    # built in normal gems) uses fileno, which musl hides without a
    # POSIX feature macro (glibc is lenient). Upstream fix pending in
    # the C repo; this stays on the throwaway instrumented build.
    # single-quote the value: it now carries a space, and an unquoted
    # split hands cmake a bare -D_GNU_SOURCE (parse error). Non-Windows
    # branch only, so sh quoting is safe.
    pgo_cflags = "#{cflags} -D_GNU_SOURCE".strip
    pgo_base = cmake_base.sub("-DCMAKE_C_FLAGS=#{cflags}",
                              "-DCMAKE_C_FLAGS='#{pgo_cflags}'")
    sh "cmake -B #{build}/build -S #{build} #{pgo_base} " \
       "-DLEPTRIS_BUILD_CLI=ON -DLEPTRIS_ENABLE_PGO=GENERATE"
    sh "cmake --build #{build}/build --config Release -j 4"
    cli = File.join(build, "build", "cli", "leptris")
    pgo_dir = File.join(build, "build", "pgo-data")
    corpus = Dir[File.join(build, "benchmarks", "data", "*.xml")]
    corpus.each do |xml|
      # a corpus file can be deliberately malformed; training tolerates it
      system({ "LLVM_PROFILE_FILE" => File.join(pgo_dir, "%p.profraw") },
             cli, "parse", xml, out: File::NULL, err: File::NULL)
    end
    if RUBY_PLATFORM =~ /darwin/
      sh "xcrun llvm-profdata merge -output=#{File.join(pgo_dir, 'default.profdata')} " \
         "#{File.join(pgo_dir, '*.profraw')}"
    end
    sh "cmake -B #{build}/build -S #{build} #{cmake_base} " \
       "-DLEPTRIS_BUILD_CLI=OFF -DLEPTRIS_ENABLE_PGO=USE"
    sh "cmake --build #{build}/build --config Release -j 4"
  else
    sh "cmake -B #{build}/build -S #{build} #{cmake_base}"
    sh "cmake --build #{build}/build --config Release -j 4"
  end
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

  # Opt-in native read layer ext (#185): built and vendored beside
  # the library — no compile at install; resolves libleptris at
  # require time via dlsym.
  if Gem.win_platform?
    # #207: a PE DLL cannot leave Ruby imports unresolved — it
    # binds the build Ruby's x64-ucrt-rubyNNN.dll. The Windows
    # gems therefore ship one DLL per supported Ruby minor
    # (native-<minor>.so), and native_layer picks by RUBY_VERSION
    # (#227). Local compile builds just the current minor's DLL;
    # the release workflow runs the build script under 3.3/3.4/
    # 4.0 to produce the full set.
    sh "#{RbConfig.ruby} ext/build_windows_native.rb"
  else
    ext_dir = "ext/leptris/native"
    Dir.chdir(ext_dir) do
      sh "ruby extconf.rb"
      if RUBY_PLATFORM =~ /darwin/
        # Link the bundle ourselves: setup-ruby's custom rubies
        # make mkmf link libruby by absolute runner path no matter
        # which RbConfig entries are cleared, and any libruby
        # LC_LOAD_DYLIB is unresolvable on user machines. Compile
        # via the Makefile, link with pure -undefined
        # dynamic_lookup (Ruby symbols resolve from the loading
        # interpreter) and a conservative deployment target.
        sh "make native.o"
        sh "cc -dynamic -bundle -undefined dynamic_lookup " \
           "-mmacosx-version-min=#{ENV['MACOSX_DEPLOYMENT_TARGET'] || '11.0'} " \
           "-o native.bundle native.o"
      else
        # #207: the darwin contract on Linux too — mkmf's `make`
        # linked libruby.so.3.3 (plus a runner runpath), which
        # failed to load on 3.4/4.0. Link WITHOUT libruby: one
        # .so serves every Ruby minor; rb_* resolve from the
        # loading interpreter at dlopen (static rubies export
        # their symbols via -rdynamic, like any extension .so).
        sh "make native.o"
        sh "#{RbConfig::CONFIG['CC']} -shared -fPIC -o native.so native.o"
        # Guard the contract in the build log.
        sh "if strings native.so | grep -q libruby; then " \
           "echo 'ERROR: native.so links libruby (#207)'; exit 1; fi"
      end
    end
    bundle = Dir.glob("#{ext_dir}/native.{bundle,so,dll}").first
    raise "native layer bundle not found after build" unless bundle
    if RUBY_PLATFORM =~ /darwin/
      # Build-log proof of the linkage contract: libSystem only.
      puts `otool -L #{bundle}`
    end
    # Atomic replace: overwriting a bundle another process still
    # has mapped gets that loader SIGKILLed (CODESIGNING Invalid
    # Page) — cp to a temp name, then mv.
    dest = "lib/leptris/xml/#{File.basename(bundle)}"
    cp(bundle, "#{dest}.new")
    mv("#{dest}.new", dest)
    puts "Vendored native layer (#{File.basename(bundle)}) into lib/leptris/xml/"
  end
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

desc "Define the gem task to build the ruby-platform gem"
task "platform:any" do
  spec = Gem::Specification::load("leptris.gemspec").dup
  # Zero-setup TruffleRuby/JRuby (#160): per-OS binaries staged
  # under lib/leptris/vendor/<platform>/ by the release assembly
  # (or by hand: cp from each platform build). Absent on a plain
  # checkout — the variant then carries no binaries and the
  # system-library / LEPTRIS_LIB_PATH path applies as before.
  spec.files += Dir.glob("lib/leptris/vendor/**/*")
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
    if platform.include?("mingw")
      # #207/#227: per-Ruby-minor DLLs (PE must bind its Ruby).
      # DOT-FREE names — MRI derives the init symbol from the
      # basename cut at the first dot (native_3_3.so ->
      # Init_native_3_3; the dotted form made Ruby look for
      # "Init_native-3", which cannot exist).
      spec.files += Dir.glob("lib/leptris/xml/native_*.so")
    else
      spec.files += Dir.glob("lib/leptris/xml/native.{bundle,so,dll}")
    end
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
