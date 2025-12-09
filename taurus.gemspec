# frozen_string_literal: true

require_relative "lib/taurus/version"

Gem::Specification.new do |spec|
  spec.name = "taurus"
  spec.version = Taurus::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Ultra-fast XML parser with full XPath support and CLI"
  spec.description = <<~DESC
    Taurus is a next-generation XML parser for Ruby with complete XPath 1.0
    support and command-line interface. Built in C for maximum performance,
    it delivers Ox-level parsing speed with full namespace support and XPath
    queries that are competitive with Nokogiri. Features: complete XPath 1.0
    (27 functions, 13 axes), XML pretty-printing CLI, zero external dependencies.
  DESC
  spec.homepage = "https://github.com/lutaml/taurus"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/lutaml/taurus"
  spec.metadata["changelog_uri"] = "https://github.com/lutaml/taurus/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "bin"
  spec.executables = ["taurus"]
  spec.require_paths = ["lib"]
  
  # Runtime dependencies
  spec.add_dependency "ffi", "~> 1.15"
  spec.add_dependency "thor", "~> 1.0"
end
