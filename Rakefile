# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Pin for `rake compile` and the platform-gem builds. Keep in lockstep
# with .github/workflows/build.yml (which calls `rake compile`) and the
# CHANGELOG when libleptris releases.
LIBLEPTRIS_VERSION = "1.5.0"

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

desc "Build libleptris #{LIBLEPTRIS_VERSION} from its release tarball into lib/"
task :compile do
  version = ENV.fetch("LIBLEPTRIS_VERSION", LIBLEPTRIS_VERSION)
  build = File.expand_path("tmp/libleptris-#{version}", __dir__)
  rm_rf(build)
  mkdir_p(build)
  url = "https://api.github.com/repos/leptris/leptris/tarball/v#{version}"
  sh "curl -sL #{url} | tar xz -C #{build} --strip-components=1"
  sh "cmake -B #{build}/build -S #{build} #{CMAKE_FLAGS.join(' ')}"
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
  puts "Vendored #{File.basename(lib)} as lib/libleptris#{ext}"
end

task spec: :compile unless ENV.key?("LEPTRIS_LIB_PATH")

task default: :spec

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
    task = Gem::PackageTask.new(spec)
    task.define
  end
end

require "rake/clean"

CLOBBER.include("pkg")
CLEAN.include("tmp",
              "lib/libleptris.dll",
              "lib/libleptris.dylib",
              "lib/libleptris.so")
