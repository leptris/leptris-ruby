# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "rbconfig"
require "rubygems/package"

# Run against the actual packaged bytes, not the source checkout. The release
# loop builds other Ruby minors immediately before the job Ruby packages again.
gem_path = File.expand_path(ARGV.fetch(0))
minor = RUBY_VERSION[/\A\d+\.\d+/].tr(".", "_")
root = File.expand_path("../../.native-abi-smoke/ruby-#{minor}", __dir__)
FileUtils.mkdir_p(root)
Gem::Package.new(gem_path).extract_files(root)
$LOAD_PATH.unshift(File.join(root, "lib"))
require "leptris"
require "leptris/xml/native_layer"

abort "native layer unavailable" unless defined?(Leptris::XML::NATIVE_FAST)
expected = File.join(root, "lib", "leptris", "xml", "native_#{minor}.so")
loaded = $LOADED_FEATURES.find { |path| File.expand_path(path) == expected }
abort "packaged native_#{minor}.so was not loaded" unless loaded

def check_document(index)
  document = Leptris::XML::Document.parse("<root><value>#{index}</value></root>")
  abort "native parse corrupted content" unless document.root.element_children.first.content == index.to_s
  document.free if index.even?
end

80.times do |index|
  check_document(index)
  GC.start(full_mark: true, immediate_sweep: true) if (index % 8).zero?
end
GC.start(full_mark: true, immediate_sweep: true)

puts JSON.pretty_generate(
  ruby: RUBY_VERSION,
  ruby_headers: RbConfig::CONFIG.fetch("rubyhdrdir"),
  compiler: RbConfig::CONFIG.fetch("CC"),
  loaded_dependencies: Gem.loaded_specs.transform_values { |spec| spec.version.to_s },
  gem_version: Leptris::VERSION,
  native_bundle: loaded,
  native_sha256: Digest::SHA256.file(loaded).hexdigest,
  packaged_variants: Dir.glob(File.join(root, "lib", "leptris", "xml", "native_*.so")).to_h do |path|
    [File.basename(path), Digest::SHA256.file(path).hexdigest]
  end,
  parse_free_gc_iterations: 80
)
