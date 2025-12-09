# frozen_string_literal: true

# This file is loaded from lib/taurus.rb after the main Taurus module is defined
# No need to require anything here - Taurus module is already available

module Taurus
  module Adapter
    class Taurus < Moxml::Adapter::Base
      class << self
        def parse(xml, _options = {})
          ::Taurus.parse(xml)
        rescue ::Taurus::ParseError => e
          raise Moxml::ParseError.new(
            e.message,
            source: xml.is_a?(String) ? xml[0..100] : nil,
          )
        end

        def xpath(node, expression, namespaces = {})
          # Taurus now has complete XPath 1.0 support through C extension
          # Use the built-in xpath method
          result = node.xpath(expression)
          
          # Ensure result is wrapped in NodeSet
          case result
          when Array
            ::Taurus::NodeSet.new(result)
          when ::Taurus::NodeSet
            result
          else
            # Scalar values (string, number, boolean) - return as-is
            result
          end
        end

        def at_xpath(node, expression, namespaces = {})
          result = xpath(node, expression, namespaces)
          result.is_a?(::Taurus::NodeSet) ? result.first : result
        end

        def xpath_supported?
          true # Taurus has complete XPath 1.0 support
        end

        def capabilities
          {
            # Core adapter capabilities
            parse: true,

            # Parsing capabilities
            sax_parsing: false,
            namespace_aware: true,
            namespace_support: :full,
            dtd_support: false,
            parsing_speed: :fast,

            # XPath capabilities - COMPLETE XPath 1.0 in C!
            xpath_support: :full,
            xpath_full: true,
            xpath_axes: :complete, # All 13 XPath 1.0 axes
            xpath_functions: :complete, # All 27 XPath 1.0 functions
            xpath_predicates: true,
            xpath_namespaces: true,
            xpath_variables: true,

            # Serialization capabilities
            namespace_serialization: true,
            pretty_print: true,

            # Known limitations
            schema_validation: false,
            xslt_support: false,
          }
        end
      end
    end
    
    # For backward compatibility
    TaurusAdapter = Taurus
  end
end
