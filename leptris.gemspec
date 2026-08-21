# frozen_string_literal: true

require_relative "lib/leptris/version"

Gem::Specification.new do |spec|
  spec.name = "leptris"
  spec.version = Leptris::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Nokogiri-compatible Ruby binding for libleptris (XML 1.0, XPath 1.0, SAX)"
  spec.description = <<~DESC
    Leptris is a Nokogiri-compatible Ruby binding for libleptris, a pure-C99 XML
    1.0 parser with full XPath 1.0 and SAX support. The C DOM is the single
    source of truth; Ruby objects are thin FFI wrappers (one Ruby method =
    one FFI call).
  DESC
  spec.homepage = "https://github.com/leptris/leptris-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/leptris/leptris-ruby",
    "changelog_uri" => "https://github.com/leptris/leptris-ruby/blob/main/CHANGELOG.md",
  }

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "bin"
  spec.executables = []
  spec.require_paths = ["lib"]

  spec.add_dependency "ffi", "~> 1.15"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
