# frozen_string_literal: true

module Leptris
  module XML
    # Minimal CSS-to-XPath translator covering the common Nokogiri subset:
    #
    #   tag                    → //tag
    #   *                      → //*
    #   .class                 → //*[contains(concat(' ',@class,' '),' class ')]
    #   #id                    → //*[@id='id']
    #   [attr]                 → //*[@attr]
    #   [attr=val]             → //*[@attr='val']
    #   tag[attr]              → //tag[@attr]
    #   tag[attr=val]          → //tag[@attr='val']
    #   parent > child         → //parent/child
    #   ancestor descendant    → //ancestor//descendant
    #   a, b                   → //a | //b
    #   tag:first-child        → //tag[position()=1]
    #   tag:last-child         → //tag[position()=last()]
    #   tag:not(simple)        → //tag[not(self::simple)]
    #
    # For anything beyond this subset, raise ArgumentError. Callers can fall
    # back to writing XPath directly via #xpath/#at_xpath.
    module CssToXPath
      COMMA_SPLIT = /\s*,\s*/.freeze
      private_constant :COMMA_SPLIT

      # Token types in a single simple selector.
      # tag (optional), then zero or more of: .class, #id, [attr...], :pseudo
      TAG_RE        = /\A(\*|[\w-]+)/.freeze
      DOT_CLASS_RE  = /\A\.([\w-]+)/.freeze
      HASH_ID_RE    = /\A#([\w-]+)/.freeze
      BRACKET_RE    = /\A\[([^\]]+)\]/.freeze
      PSEUDO_RE     = /\A:([\w-]+(?:\([^)]*\))?)/.freeze

      module_function

      # Translation is a pure function of the rule string, and real
      # workloads repeat a small selector vocabulary in loops —
      # memoize. Failed translations raise before caching.
      CACHE = {}
      private_constant :CACHE

      def convert(rule)
        key = rule.to_s
        CACHE.fetch(key) { CACHE[key] = convert_rule(key) }
      end

      def convert_rule(rule)
        rule.split(COMMA_SPLIT).map { |r| convert_one(r.strip) }.join(" | ")
      end

      def convert_one(rule)
        return "//*" if rule == "*"

        # Tokenize chain first (handles > and whitespace)
        if rule =~ /\s/ || rule.include?(">")
          return convert_chain(rule)
        end

        convert_simple(rule, prefix: "//")
      end

      # Parse a single simple selector into (tag, predicates) where
      # predicates is an array of XPath fragments to be joined via [p1][p2]...
      def parse_simple(part)
        tag = "*"
        preds = []

        s = part.strip
        if s =~ TAG_RE
          tag = $1
          s = $'
        end

        until s.empty?
          case s
          when DOT_CLASS_RE
            preds << "contains(concat(' ',normalize-space(@class),' '),' #{$1} ')"
            s = $'
          when HASH_ID_RE
            preds << "@id='#{$1}'"
            s = $'
          when BRACKET_RE
            preds << convert_attrs($1)
            s = $'
          when PSEUDO_RE
            preds << convert_pseudo($1)
            s = $'
          else
            raise ArgumentError,
              "unsupported CSS selector at #{s.inspect} (in #{part.inspect})"
          end
        end

        [tag, preds]
      end

      def convert_simple(part, prefix:)
        tag, preds = parse_simple(part)
        "#{prefix}#{tag}#{preds.map { |p| "[#{p}]" }.join}"
      end
      private_class_method :convert_simple

      def convert_attrs(clause)
        case clause.strip
        when /\A(\w+)\z/
          "@#{$1}"
        when /\A(\w+)=['"]?([^'"\]]+)['"]?\z/
          "@#{$1}='#{$2}'"
        when /\A(\w+)~=['"]?([^'"\]]+)['"]?\z/
          "contains(concat(' ',normalize-space(@#{$1}),' '),' #{$2} ')"
        when /\A(\w+)\^=['"]?([^'"\]]+)['"]?\z/
          "starts-with(@#{$1}, '#{$2}')"
        when /\A(\w+)\$=['"]?([^'"\]]+)['"]?\z/
          "substring(@#{$1}, string-length(@#{$1}) - string-length('#{$2}') + 1) = '#{$2}'"
        when /\A(\w+)\*=['"]?([^'"\]]+)['"]?\z/
          "contains(@#{$1}, '#{$2}')"
        else
          raise ArgumentError, "unsupported attribute selector: [#{clause}]"
        end
      end
      private_class_method :convert_attrs

      def convert_pseudo(pseudo)
        case pseudo
        when "first-child"     then "not(preceding-sibling::*)"
        when "last-child"      then "not(following-sibling::*)"
        when "only-child"      then "not(preceding-sibling::* or following-sibling::*)"
        when "empty"           then "not(node())"
        when "root"            then "not(parent::*)"
        when /\Anot\((.+)\)\z/
          inner_tag, _ = parse_simple($1)
          "not(self::#{inner_tag})"
        else
          raise ArgumentError, "unsupported pseudo-class: :#{pseudo}"
        end
      end
      private_class_method :convert_pseudo

      # Tokenize chain into [sel, op, sel, op, sel, ...] where op is :child or
      # :descendant. Then build XPath.
      def convert_chain(rule)
        tokens = tokenize_chain(rule)
        build_chain_xpath(tokens)
      end
      private_class_method :convert_chain

      def tokenize_chain(rule)
        tokens = []
        s = rule.strip
        until s.empty?
          if s.sub!(/\A\s*>\s*/, "")
            tokens << :child
          elsif s.sub!(/\A\s+/, "")
            # whitespace descendant only counts if previous token is a string
            tokens << :descendant if tokens.last.is_a?(String)
          else
            # Read one simple selector — keep going until whitespace or > or end
            m = s.match(/\A[^>\s]+/)
            raise ArgumentError, "couldn't parse CSS chain at: #{s.inspect}" unless m
            tokens << m[0]
            s = m.post_match
          end
        end
        tokens
      end
      private_class_method :tokenize_chain

      def build_chain_xpath(tokens)
        first = tokens.shift
        raise ArgumentError, "empty CSS chain" unless first.is_a?(String)

        xpath = convert_simple(first, prefix: "//")
        until tokens.empty?
          op = tokens.shift
          sel = tokens.shift
          raise ArgumentError, "malformed CSS chain" unless sel.is_a?(String)
          inner_tag, preds = parse_simple(sel)
          connector = op == :child ? "/" : "//"
          xpath = "#{xpath}#{connector}#{inner_tag}#{preds.map { |p| "[#{p}]" }.join}"
        end
        xpath
      end
      private_class_method :build_chain_xpath
    end
  end
end
