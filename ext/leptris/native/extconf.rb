# frozen_string_literal: true

# The bundle must load into ANY Ruby (not the building runner's):
# macOS links with -undefined dynamic_lookup (Ruby symbols resolve
# from the loading interpreter — the standard C-ext convention)
# and a conservative deployment target; libruby is never linked.
ENV["MACOSX_DEPLOYMENT_TARGET"] ||= "11.0"
require "mkmf"
if RUBY_PLATFORM =~ /darwin/
  $LDFLAGS << " -undefined dynamic_lookup"
end
create_makefile("leptris/xml/native")
