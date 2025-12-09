# frozen_string_literal: true

require "thor"
require_relative "../taurus"
require_relative "commands/xpath_command"
require_relative "commands/format_command"

module Taurus
  # Taurus CLI - Command-line interface for XML processing
  #
  # Provides fast XML parsing, XPath queries, and formatting capabilities
  # through a simple command-line interface.
  #
  # Architecture:
  # - CLI layer uses Thor for option parsing
  # - All logic delegated to Command classes
  # - Commands use API classes (Document, Element, etc.)
  # - MECE design: CLI/API/ENV argument handling
  class CLI < Thor
    # Global options available to all commands
    class_option :quiet,
                 type: :boolean,
                 aliases: "-q",
                 desc: "Suppress output messages"
    
    class_option :verbose,
                 type: :boolean,
                 aliases: "-v",
                 desc: "Show verbose output"

    desc "xpath FILE EXPRESSION", "Execute XPath query against XML file"
    long_desc <<~DESC
      Execute an XPath 1.0 query against an XML document.
      
      Supports:
      - All XPath 1.0 axes, functions, and operators
      - Complete namespace support
      - Multiple output formats
      - Stdin input (use '-' as filename)
      
      Examples:
        $ taurus xpath books.xml "//book"
        $ cat books.xml | taurus xpath - "//title"
        $ taurus xpath --count books.xml "//book[@price > 20]"
    DESC
    method_option :count,
                  type: :boolean,
                  aliases: "-c",
                  desc: "Output count of matching nodes"
    method_option :boolean,
                  type: :boolean,
                  aliases: "-b",
                  desc: "Output boolean result (true/false)"
    method_option :format,
                  type: :string,
                  aliases: "-f",
                  enum: %w[text xml count boolean],
                  default: "xml",
                  desc: "Output format"
    def xpath(file, expression)
      Commands::XPathCommand.new(options).run(file, expression)
    rescue Taurus::Error => e
      handle_error(e)
    end

    desc "format FILE", "Pretty-print XML document"
    long_desc <<~DESC
      Format an XML document with proper indentation.
      
      Features:
      - Customizable indentation (default: 2 spaces)
      - Compact mode (removes extra whitespace)
      - Output to file or stdout
      - Preserves namespace declarations
      
      Examples:
        $ taurus format books.xml
        $ taurus format --indent 4 books.xml
        $ taurus format --output formatted.xml books.xml
        $ taurus format --compact books.xml
    DESC
    method_option :indent,
                  type: :numeric,
                  aliases: "-i",
                  default: 2,
                  desc: "Indentation spaces"
    method_option :output,
                  type: :string,
                  aliases: "-o",
                  desc: "Output file (default: stdout)"
    method_option :compact,
                  type: :boolean,
                  desc: "Remove extra whitespace"
    def format(file)
      Commands::FormatCommand.new(options).run(file)
    rescue Taurus::Error => e
      handle_error(e)
    end

    desc "version", "Show Taurus version"
    def version
      puts "Taurus #{Taurus::VERSION}"
      puts "Fast XML parser with complete XPath 1.0 support"
    end

    private

    def handle_error(error)
      if options[:verbose]
        warn "Error: #{error.message}"
        warn error.backtrace.join("\n") if error.backtrace
      elsif !options[:quiet]
        warn "Error: #{error.message}"
      end
      exit 1
    end
  end
end