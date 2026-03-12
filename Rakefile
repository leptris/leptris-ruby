# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "fileutils"

# Build task for libtaurus FFI library
desc "Compile libtaurus library"
task :compile do
  ext_dir = File.expand_path('ext/taurus', __dir__)
  Dir.chdir(ext_dir) do
    ruby 'extconf.rb'
  end
end

# Ruby tests
RSpec::Core::RakeTask.new(:spec)
task spec: :compile

# Clean build artifacts
desc "Clean build artifacts"
task :clean do
  FileUtils.rm_f(Dir.glob("lib/libtaurus.{so,bundle,dll,dylib}"))
  FileUtils.rm_rf("ext/taurus/build")
  FileUtils.rm_f("ext/taurus/Makefile")
  FileUtils.rm_rf(["tmp", "pkg"])
  puts "Cleaned build artifacts"
end

# All tests
desc "Run all tests"
task test: :spec do
  puts "\n" + "=" * 80
  puts "TEST SUITE COMPLETE"
  puts "=" * 80
end

# Default task
task default: :test