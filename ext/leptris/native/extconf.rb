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

begin
  require "mkmf"
rescue LoadError
  File.write("Makefile", <<~MAKE)
    all install clean:
    \t@echo "leptris: no mkmf on this engine — skipping the native extension; the FFI surface applies"
  MAKE
  warn "leptris: mkmf unavailable (#{RUBY_ENGINE}) — installing without the compiled native layer"
  exit 0
end

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
  # setup-ruby builds carry the RUNNER's absolute libruby path in
  # LIBRUBYARG_SHARED — recorded as an LC_LOAD_DYLIB in the
  # bundle, unresolvable on user machines. A Ruby extension
  # resolves Ruby symbols from the loading interpreter; never
  # link libruby.
  # BOTH maps: mkmf's Makefile interpolates from MAKEFILE_CONFIG,
  # not CONFIG — clearing only CONFIG is a silent no-op (caught via
  # the build-log otool on the runner).
  RbConfig::CONFIG["LIBRUBYARG_SHARED"] = ""
  RbConfig::CONFIG["LIBRUBYARG_STATIC"] = ""
  RbConfig::MAKEFILE_CONFIG["LIBRUBYARG_SHARED"] = ""
  RbConfig::MAKEFILE_CONFIG["LIBRUBYARG_STATIC"] = ""
end
if Gem.win_platform?
  # Windows names the artifact per Ruby minor, DOT-FREE (#227
  # fix): MRI derives the init symbol from the basename cut at
  # the first dot, so native_3_4.so needs Init_native_3_4
  # exported. GNU ld auto-exports only when no explicit export
  # is present — pin the export table with a .def file so the
  # wrapper init names are certain to be exported.
  def_path = File.expand_path("native_exports.def", __dir__)
  File.write(def_path, <<~DEF)
    EXPORTS
    Init_native
    Init_native_3_3
    Init_native_3_4
    Init_native_4_0
  DEF
  win_def = " #{def_path.tr('/', '\\\\')}"
  $DLDFLAGS << win_def unless $DLDFLAGS.include?("native_exports.def")
end
create_makefile("leptris/xml/native")
