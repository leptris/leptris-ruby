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
end
create_makefile("leptris/xml/native")
