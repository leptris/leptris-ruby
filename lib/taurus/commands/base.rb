# frozen_string_literal: true

module Taurus
  module Commands
    # Base class for all Taurus commands
    #
    # Provides common functionality:
    # - File/stdin reading
    # - Error handling
    # - Option access
    # - Output management
    class Base
      attr_reader :options

      def initialize(options = {})
        @options = options
      end

      # Read XML from file or stdin
      #
      # @param filename [String] File path or '-' for stdin
      # @return [String] XML content
      def read_input(filename)
        if filename == "-"
          $stdin.read
        else
          File.read(filename)
        end
      rescue Errno::ENOENT
        raise Taurus::Error, "File not found: #{filename}"
      rescue Errno::EACCES
        raise Taurus::Error, "Permission denied: #{filename}"
      rescue => e
        raise Taurus::Error, "Failed to read file: #{e.message}"
      end

      # Parse XML string
      #
      # @param xml [String] XML content
      # @return [Taurus::Document] Parsed document
      def parse_xml(xml)
        Taurus.parse(xml)
      rescue Taurus::ParseError => e
        raise Taurus::Error, "XML parse error: #{e.message}"
      end

      # Write output to file or stdout
      #
      # @param content [String] Content to write
      # @param filename [String, nil] Output file or nil for stdout
      def write_output(content, filename = nil)
        if filename
          File.write(filename, content)
          log_info "Output written to #{filename}" if options[:verbose]
        else
          puts content
        end
      rescue => e
        raise Taurus::Error, "Failed to write output: #{e.message}"
      end

      # Log info message (unless quiet)
      def log_info(message)
        warn message unless options[:quiet]
      end

      # Log verbose message (only if verbose)
      def log_verbose(message)
        warn message if options[:verbose]
      end
    end
  end
end