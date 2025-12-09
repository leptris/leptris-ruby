# frozen_string_literal: true

require_relative "base"

module Taurus
  module Commands
    # Format command - Pretty-print XML documents
    #
    # Provides XML formatting with customizable indentation.
    # Can output to stdout or file.
    #
    # Usage:
    #   command = FormatCommand.new(options)
    #   command.run("books.xml")
    class FormatCommand < Base
      # Format XML document
      #
      # @param filename [String] XML file path or '-' for stdin
      def run(filename)
        log_verbose "Reading XML from #{filename == '-' ? 'stdin' : filename}..."
        xml = read_input(filename)
        
        log_verbose "Parsing XML..."
        doc = parse_xml(xml)
        
        log_verbose "Formatting XML..."
        formatted = format_document(doc)
        
        write_output(formatted, options[:output])
      end

      private

      # Format document based on options
      def format_document(doc)
        if options[:compact]
          format_compact(doc)
        else
          format_pretty(doc)
        end
      end

      # Format with indentation
      def format_pretty(doc)
        indent = options[:indent] || 2
        indent_str = " " * indent
        
        xml = +""  # Unfreeze string
        
        # Add XML declaration if present
        if doc.respond_to?(:version) && doc.version
          xml << %{<?xml version="#{doc.version}"}
          xml << %{ encoding="#{doc.encoding}"} if doc.encoding
          xml << "?>\n"
        end
        
        # Format root element
        xml << format_element(doc.root, 0, indent_str)
        xml << "\n"
        
        xml
      end

      # Format element with indentation
      def format_element(element, depth, indent_str)
        return +"" unless element
        
        indent = indent_str * depth
        xml = +"#{indent}<#{element.name}"
        
        # Add attributes
        if element.attributes && !element.attributes.empty?
          element.attributes.each do |key, value|
            xml << %( #{key}="#{escape_xml(value)}")
          end
        end
        
        # Handle empty elements
        if element.nodes.empty?
          xml << "/>"
          return xml
        end
        
        # Check if element has only text content
        if has_only_text?(element)
          xml << ">"
          text = element.nodes.find { |n| n.is_a?(String) }
          xml << escape_xml(text) if text
          xml << "</#{element.name}>"
          return xml
        end
        
        xml << ">\n"
        
        # Format children
        element.nodes.each do |child|
          case child
          when Element
            xml << format_element(child, depth + 1, indent_str)
            xml << "\n"
          when String
            # Only add text if non-whitespace
            text = child.strip
            unless text.empty?
              xml << "#{indent}#{indent_str}#{escape_xml(text)}\n"
            end
          end
        end
        
        xml << "#{indent}</#{element.name}>"
        xml
      end

      # Format document in compact mode (no extra whitespace)
      def format_compact(doc)
        xml = +""
        
        # Add XML declaration if present
        if doc.respond_to?(:version) && doc.version
          xml << %{<?xml version="#{doc.version}"}
          xml << %{ encoding="#{doc.encoding}"} if doc.encoding
          xml << "?>"
        end
        
        # Format root element
        xml << format_element_compact(doc.root)
        xml
      end

      # Format element in compact mode
      def format_element_compact(element)
        return +"" unless element
        
        xml = +"<#{element.name}"
        
        # Add attributes
        if element.attributes && !element.attributes.empty?
          element.attributes.each do |key, value|
            xml << %( #{key}="#{escape_xml(value)}")
          end
        end
        
        # Handle empty elements
        if element.nodes.empty?
          xml << "/>"
          return xml
        end
        
        xml << ">"
        
        # Add children (remove whitespace-only text)
        element.nodes.each do |child|
          case child
          when Element
            xml << format_element_compact(child)
          when String
            # Only add non-whitespace text
            text = child.strip
            xml << escape_xml(text) unless text.empty?
          end
        end
        
        xml << "</#{element.name}>"
        xml
      end

      # Check if element contains only text content (no child elements)
      def has_only_text?(element)
        return false if element.nodes.empty?
        
        element.nodes.all? do |node|
          node.is_a?(String)
        end
      end

      # Escape XML special characters
      def escape_xml(text)
        text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub('"', "&quot;")
          .gsub("'", "&apos;")
      end
    end
  end
end