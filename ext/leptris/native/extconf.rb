# frozen_string_literal: true

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
