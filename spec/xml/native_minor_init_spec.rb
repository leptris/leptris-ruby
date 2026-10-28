# frozen_string_literal: true

require "leptris"

RSpec.describe "per-minor native bundle init symbol (Ruby 4.x support)" do
  # native_layer requires leptris/xml/native_<major>_<minor>; MRI
  # derives the init symbol from that basename, so the bundle built
  # under the RUNNING Ruby must export Init_native_<major>_<minor>.
  # The formerly hardcoded thunk list (3_1..4_0) made every Ruby
  # newer than the list compile the sdist yet fail its own
  # dlsym(Init_native_4_1), silently dropping to FFI with a "not
  # available in this install" warning — reported as "no Ruby 4.x
  # support". The thunk is now generated from the build's API
  # version, so this spec holds on every future minor.
  it "exports the init symbol for the running minor" do
    minor = RUBY_VERSION[/\A\d+\.\d+/].tr(".", "_")
    ext = RUBY_PLATFORM.include?("darwin") ? ".bundle" : ".so"
    bundle = File.expand_path(
      "../../lib/leptris/xml/native_#{minor}#{ext}", __dir__
    )
    skip "no bundle for this minor in this checkout (#{bundle})" unless
      File.exist?(bundle)

    lib = FFI::DynamicLibrary.new(
      bundle, FFI::DynamicLibrary::RTLD_LAZY | FFI::DynamicLibrary::RTLD_LOCAL
    )
    expect(lib.find_function("Init_native_#{minor}")).not_to be_nil
  end
end
