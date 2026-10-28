# frozen_string_literal: true

# Install-time build orchestration for the SOURCE (ruby-platform)
# gem: compile libleptris (+ utf8proc) from the vendored
# vendor-src/ trees via cmake, then build the native C extension
# against nothing (dynamic_lookup — it dlopens the same library
# the FFI layer loads). Graceful degradation is the contract:
#   - no mkmf (JRuby): emit a no-op Makefile; the gem installs and
#     runs on the vendored binaries / FFI (#160 path).
#   - no cmake / build failure: warn and build only the extension;
#     native_layer's resolve! falls back loudly to the FFI surface
#     (vendored binaries or system library).
# Platform gems ship the same sources but never run this at
# install (they carry no extensions) — recompile rights only.
gem_root = File.expand_path("../../..", __dir__) # <gem>/ext/leptris/native
lib_dir = File.join(gem_root, "lib")
vendored = File.join(gem_root, "vendor-src")

# Only engines that genuinely build MRI C extensions attempt the
# build. JRuby carries an mkmf STUB: require succeeds, but the
# generated Makefile fails on ruby.h — route it to the no-op too.
unless %w[ruby truffleruby].include?(RUBY_ENGINE)
  File.write("Makefile", <<~MAKE)
    all install clean:
    \t@echo "leptris: no MRI C-ext toolchain on #{RUBY_ENGINE} — skipping the native extension; the FFI surface applies"
  MAKE
  warn "leptris: #{RUBY_ENGINE} cannot build MRI C extensions — " \
       "installing without the compiled native layer"
  exit 0
end
# Never link libruby: a Ruby extension resolves rb_* symbols from
# the LOADING interpreter, and mkmf records the building ruby's
# libruby (for setup-ruby, an absolute hostedtoolcache path) into
# the bundle otherwise — dlopen-failing on every other machine
# (#1739). mkmf snapshots $LIBRUBYARG* from RbConfig at require
# time, so this MUST precede `require "mkmf"`; a later clearing is
# a silent no-op (exactly how the 1.9.36x trains shipped broken).
if RUBY_PLATFORM =~ /darwin/
  %w[LIBRUBYARG LIBRUBYARG_SHARED LIBRUBYARG_STATIC].each do |key|
    RbConfig::CONFIG[key] = ""
    RbConfig::MAKEFILE_CONFIG[key] = ""
  end
end
require "mkmf"

# A prebuilt libleptris in lib/ (dev checkout after rake compile,
# or any context that already provides one) means this extconf is
# NOT an sdist install — skip the orchestration entirely (it also
# keeps rake compile from redundantly rebuilding the engine into
# vendor-src/).
prebuilt = Dir.glob(File.join(lib_dir, "libleptris.{so,dylib,dll}")).first
if !prebuilt && File.directory?(File.join(vendored, "libleptris")) &&
   find_executable("cmake")
  begin
    u8_src = File.join(vendored, "utf8proc")
    u8_bld = File.join(vendored, "utf8proc-build")
    u8_pre = File.join(vendored, "utf8proc-prefix")
    FileUtils.mkpath(u8_bld)
    sh_ok = lambda do |*cmd|
      system(*cmd.map(&:to_s)) or raise "command failed: #{cmd.join(' ')[0, 120]}"
    end
    sh_ok.call("cmake", "-B", u8_bld, "-S", u8_src,
               "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_SHARED_LIBS=ON",
               "-DUTF8PROC_ENABLE_TESTING=OFF")
    sh_ok.call("cmake", "--build", u8_bld, "--config", "Release", "-j",
               ENV.fetch("MAKEFLAGS", "-j4").split.first || "-j4")
    sh_ok.call("cmake", "--install", u8_bld, "--prefix", u8_pre)

    eng_src = File.join(vendored, "libleptris")
    eng_bld = File.join(vendored, "libleptris-build")
    FileUtils.mkpath(eng_bld)
    sh_ok.call("cmake", "-B", eng_bld, "-S", eng_src,
               "-DCMAKE_BUILD_TYPE=Release",
               "-DLEPTRIS_BUILD_SHARED=ON", "-DLEPTRIS_BUILD_STATIC=OFF",
               "-DBUILD_TESTING=OFF", "-DLEPTRIS_BUILD_CLI=OFF",
               "-DLEPTRIS_BUILD_BENCHMARKS=OFF", "-DLEPTRIS_BUILD_MAN_PAGES=OFF",
               "-DLEPTRIS_ENABLE_UTF8PROC=ON",
               "-DCMAKE_PREFIX_PATH=#{u8_pre}")
    sh_ok.call("cmake", "--build", eng_bld, "--config", "Release",
               ENV.fetch("MAKEFLAGS", "-j4").split.first || "-j4")
    built = Dir.glob(File.join(eng_bld, "**", "libleptris.{so,dylib,dll}")).first
    raise "libleptris build produced no shared library" unless built
    ext = File.extname(built)
    FileUtils.cp(built, File.join(lib_dir, "libleptris#{ext}"))
    Dir.glob(File.join(u8_pre, "lib", "libutf8proc.*")).each do |u8|
      next if File.directory?(u8)
      base = File.basename(u8)
      next if base.end_with?(".pc")
      FileUtils.cp(u8, File.join(lib_dir, base)) rescue nil
    end
    puts "leptris: compiled libleptris from source into #{lib_dir}"
  rescue StandardError => e
    warn "leptris: source build skipped (#{e.message}); the gem will " \
         "load the vendored binary or system library instead"
  end
else
  warn "leptris: cmake or vendored sources unavailable — skipping the " \
       "engine compile; vendored binaries / system library apply"
end

# The bundle must load into ANY Ruby (not the building runner's):
# macOS links with -undefined dynamic_lookup (Ruby symbols resolve
# from the loading interpreter — the standard C-ext convention)
# and a conservative deployment target; libruby is never linked.
ENV["MACOSX_DEPLOYMENT_TARGET"] ||= "11.0"
require "mkmf"
if RUBY_PLATFORM =~ /darwin/
  # Robust across mkmf versions: older rubies drop $(ldflags)
  # from the bundle link line, so pin BOTH the compile and link
  # variables. -undefined dynamic_lookup is the standard C-ext
  # convention (Ruby symbols resolve from the loading
  # interpreter); -mmacosx-version-min keeps the bundle loadable
  # on older user OSes than the building runner.
  min = " -mmacosx-version-min=#{ENV['MACOSX_DEPLOYMENT_TARGET']}"
  lookup = " -undefined dynamic_lookup"
  [$LDFLAGS, $DLDFLAGS, $CFLAGS, $CXXFLAGS].each do |var|
    var << min unless var.include?(min.strip)
  end
  [$LDFLAGS, $DLDFLAGS].each do |var|
    var << lookup unless var.include?("dynamic_lookup")
  end
  # ruby#476: newer ld64 defaults BUNDLES to two-level namespace —
  # with -undefined dynamic_lookup a two-level bind records the
  # symbol as expected from the MAIN EXECUTABLE ("main-executable"),
  # and interpreters that don't re-export every ruby symbol from
  # their binary abort at first call ("dyld missing symbol called",
  # hit at Init_native's first import). -flat_namespace is the
  # classic C-extension pattern: dynamic_lookup symbols search all
  # loaded images at call time and resolve from libruby.
  flat = " -Wl,-flat_namespace"
  [$LDFLAGS, $DLDFLAGS].each do |var|
    var << flat unless var.include?("flat_namespace")
  end
  # Belt for the require-time snapshot: RbConfig was cleared BEFORE
  # `require "mkmf"` (top of file), and the module globals mkmf
  # captured then are zeroed here too — a Ruby extension resolves
  # Ruby symbols from the loading interpreter; never link libruby.
  $LIBRUBYARG = ""
  $LIBRUBYARG_SHARED = ""
  $LIBRUBYARG_STATIC = ""
end
if Gem.win_platform?
  # Windows names the artifact per Ruby minor, DOT-FREE (#227
  # fix): MRI derives the init symbol from the basename cut at
  # the first dot, so native_3_4.so needs Init_native_3_4
  # exported. GNU ld auto-exports only when no explicit export
  # is present — pin the export table with a .def file so the
  # wrapper init names are certain to be exported.
  def_path = File.expand_path("native_exports.def", __dir__)
  # The per-minor entry follows the BUILD's Ruby version (native.c
  # generates the same name from ruby/version.h): a pinned
  # 3_3/3_4/4_0 list left newer minors (4.1) unexported on PE.
  win_minor = RUBY_VERSION[/\A\d+\.\d+/].tr(".", "_")
  File.write(def_path, <<~DEF)
    EXPORTS
    Init_native
    Init_native_#{win_minor}
  DEF
  win_def = " #{def_path.tr('/', '\\\\')}"
  $DLDFLAGS << win_def unless $DLDFLAGS.include?("native_exports.def")
end
# Name the artifact per Ruby minor EVERYWHERE (#476): the loader
# requires native_<minor> and deliberately has NO unversioned
# fallback (loading a bundle built by another minor is the 3.1
# wrong-ABI segfault class), so a source install must produce the
# per-minor name itself. mkmf derives Init_native_<minor> from the
# same basename — exported by native.c and pinned in the Windows
# .def above.
minor_us = RUBY_VERSION[/\A\d+\.\d+/].tr(".", "_")
create_makefile("leptris/xml/native_#{minor_us}")
