# frozen_string_literal: true

require_relative "base"

module Taurus
  module Commands
    # XPath query command
    #
    # Executes XPath 1.0 queries against XML documents.
    # Supports all XPath axes, functions, and operators.
    #
    # Usage:
    #   command = XPathCommand.new(options)
    #   command.run("books.xml", "//book")
    class XPathCommand < Base
      # Execute XPath query
      #
      # @param filename [String] XML file path or '-' for stdin
      # @param expression [String] XPath expression
      def run(filename, expression)
        log_verbose "Reading XML from #{filename == '-' ? 'stdin' : filename}..."
        xml = read_input(filename)
        
        log_verbose "Parsing XML..."
        doc = parse_xml(xml)
        
        log_verbose "Executing XPath: #{expression}"
        result = doc.xpath(expression)
        
        log_verbose "Query returned #{result_summary(result)}"
        
        output_result(result)
      end

      private

      # Output XPath result based on format and type
      def output_result(result)
        format = determine_format(result)
        
        case format
        when :count
          output_count(result)
        when :boolean
          output_boolean(result)
        when :number
          output_number(result)
        when :string
          output_string(result)
        when :xml
          output_xml(result)
        end
      end

      # Determine output format based on options and result type
      def determine_format(result)
        # Explicit format from options
        return :count if options[:count]
        return :boolean if options[:boolean]
        return options[:format].to_sym if options[:format]
        
        # Auto-detect from result type
        case result
        when NodeSet, Array
          :xml
        when TrueClass, FalseClass
          :boolean
        when Numeric
          :number
        when String
          :string
        else
          :xml
        end
      end

      # Output count of nodes
      def output_count(result)
        count = case result
                when NodeSet, Array
                  result.size
                when TrueClass
                  1
                when FalseClass
                  0
                else
                  1
                end
        puts count
      end

      # Output boolean result
      def output_boolean(result)
        bool = case result
               when NodeSet, Array
                 !result.empty?
               when TrueClass, FalseClass
                 result
               when Numeric
                 result != 0
               when String
                 !result.empty?
               else
                 false
               end
        puts bool ? "true" : "false"
      end

      # Output number result
      def output_number(result)
        number = case result
                 when Numeric
                   result
                 when String
                   result.to_f
                 when TrueClass
                   1.0
                 when FalseClass
                   0.0
                 else
                   0.0
                 end
        
        # Handle special float values
        if number.infinite?
          puts number > 0 ? "Infinity" : "-Infinity"
        elsif number.nan?
          puts "NaN"
        else
          puts number
        end
      end

      # Output string result
      def output_string(result)
        str = case result
              when String
                result
              when Numeric
                result.to_s
              when TrueClass
                "true"
              when FalseClass
                "false"
              when NodeSet, Array
                result.map { |n| node_to_string(n) }.join
              else
                result.to_s
              end
        puts str
      end

      # Output XML nodes
      def output_xml(result)
        nodes = case result
                when NodeSet
                  result.to_a
                when Array
                  result
                when Element
                  [result]
                else
                  return output_string(result)
                end
        
        if nodes.empty?
          log_info "XPath set is empty" unless options[:quiet]
          exit 11 # XMLLINT_ERR_XPATH_EMPTY
        end
        
        nodes.each do |node|
          puts node_to_xml(node)
        end
      end

      # Convert node to XML string
      def node_to_xml(node)
        case node
        when Element
          element_to_xml(node)
        when String
          node
        else
          node.to_s
        end
      end

      # Convert element to XML string
      def element_to_xml(element)
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
        
        # Add children
        element.nodes.each do |child|
          xml << node_to_xml(child)
        end
        
        xml << "</#{element.name}>"
        xml
      end

      # Convert node to text string (for string() function)
      def node_to_string(node)
        case node
        when Element
          element.nodes.map { |n| node_to_string(n) }.join
        when String
          node
        else
          node.to_s
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

      # Human-readable result summary
      def result_summary(result)
        case result
        when NodeSet, Array
          "#{result.size} node(s)"
        when TrueClass, FalseClass
          "boolean: #{result}"
        when Numeric
          "number: #{result}"
        when String
          "string: #{result[0...50]}#{'...' if result.length > 50}"
        else
          result.class.name
        end
      end
    end
  end
end