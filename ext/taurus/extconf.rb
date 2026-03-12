require 'mkmf'
require 'fileutils'

# Extconf for building libtaurus using CMake
# This builds the C library and installs it for FFI access

ext_dir = __dir__
lib_dir = File.expand_path('../../lib', ext_dir)
build_dir = File.join(ext_dir, 'build')

# Create build directory
FileUtils.mkdir_p(build_dir)

# Detect platform-specific library extension
lib_ext = case RUBY_PLATFORM
          when /darwin/
            'dylib'
          when /linux/
            'so'
          when /mingw|mswin/
            'dll'
          else
            'so'
          end

puts "Building libtaurus for #{RUBY_PLATFORM}..."

# Run CMake to configure the build
Dir.chdir(build_dir) do
  # Configure with CMake - disable CLI and tests, only build library
  cmake_args = [
    '-DCMAKE_BUILD_TYPE=Release',
    '-DBUILD_SHARED_LIBS=ON',
    '-DBUILD_TESTING=OFF',
    '-DTAURUS_BUILD_CLI=OFF',
    '-DTAURUS_BUILD_MAN_PAGES=OFF',
    '..'
  ]

  unless system('cmake', *cmake_args)
    raise "CMake configuration failed"
  end

  # Build
  unless system('cmake', '--build', '.', '--config', 'Release')
    raise "CMake build failed"
  end

  # Install library to lib directory where FFI can find it
  built_lib = Dir.glob("lib/libtaurus.#{lib_ext}").first ||
              Dir.glob("Release/libtaurus.#{lib_ext}").first ||
              Dir.glob("libtaurus.#{lib_ext}").first

  if built_lib && File.exist?(built_lib)
    target_lib = File.join(lib_dir, "libtaurus.#{lib_ext}")
    FileUtils.cp(built_lib, target_lib)
    puts "✓ Installed libtaurus.#{lib_ext} to #{lib_dir}"
  else
    raise "Could not find built library libtaurus.#{lib_ext}"
  end
end

# Create a dummy Makefile for gem installation compatibility
File.open('Makefile', 'w') do |f|
  f.puts "# Dummy Makefile - actual build done by CMake"
  f.puts "all:"
  f.puts "\t@echo 'Library already built by extconf.rb'"
  f.puts "install:"
  f.puts "\t@echo 'Library installed to lib/'"
  f.puts "clean:"
  f.puts "\t@echo 'Nothing to clean (use rake clean)'"
end

puts "✓ Build configuration complete"