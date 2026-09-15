# frozen_string_literal: true

module Leptris::XML::Searchable
  # Values that make a :version key the version channel (#183,
  # mirroring leptris-py#105); anything else is a namespace prefix.
  VERSION_SELECTORS = ["1.0", "3.1", :xpath10, :xpath31].freeze

  # Compiled-expression cache (TODO.perf/15): the engine caches
  # compiled strings internally, but the string path still pays
  # lookup + hashing per call — a direct handle eval measured 34%
  # under it on repeat expressions. Bounded LRU keyed on the
  # expression string; only successful compiles cache; GVL makes
  # the Hash operations safe. Version-pinned and namespace-bound
  # evaluations keep their dedicated string entries.
  COMPILED_CACHE_LIMIT = 64

  def self.compiled_expression(expr)
    cache = (@compiled_expressions ||= {})
    if (hit = cache[expr])
      cache.delete(expr)
      cache[expr] = hit # LRU refresh
      return hit
    end
    compiled = Leptris::XML::XPath.compile(expr)
    cache.shift while cache.size >= COMPILED_CACHE_LIMIT
    cache[expr] = compiled
    compiled
  rescue Leptris::XML::XPathError
    nil # fall back to the string path — its error surface is the contract
  end

  def xpath(*paths)
    handler, ns, version = parse_search_args(paths)
    raise ArgumentError, "custom XPath handlers not supported" if handler
    expr = paths.join(" | ")

    doc_ptr = is_a?(Leptris::XML::Document) ? c_ptr : document.c_ptr
    context_ptr = is_a?(Leptris::XML::Document) ? nil : c_ptr

    result_ptr =
      if version
        if ns && !ns.empty?
          raise ArgumentError,
            "version: cannot be combined with namespace bindings " \
            "(the versioned engine entry takes no ns set yet)"
        end
        Leptris::XML::FFI.leptris_xpath_eval_versioned(
          doc_ptr, context_ptr, expr,
          Leptris::XML::Searchable.xpath_version_code(version), nil)
      elsif ns && !ns.empty?
        xpath_eval_with_namespaces(doc_ptr, context_ptr, expr, ns)
      elsif (compiled = Leptris::XML::Searchable.compiled_expression(expr))
        compiled.eval_ptrs(doc_ptr, context_ptr)
      else
        Leptris::XML::FFI.leptris_xpath_eval(doc_ptr, context_ptr, expr)
      end
    if result_ptr.null?
      raise Leptris::XML::XPathError,
        Leptris::XML::FFI.leptris_last_error.to_s
    end

    Leptris::XML::Searchable.wrap_xpath_result(document, result_ptr)
  end

  def at_xpath(*paths)
    handler, ns, version = parse_search_args(paths)
    raise ArgumentError, "custom XPath handlers not supported" if handler
    expr = paths.join(" | ")

    doc_ptr = is_a?(Leptris::XML::Document) ? c_ptr : document.c_ptr
    context_ptr = is_a?(Leptris::XML::Document) ? nil : c_ptr

    result_ptr =
      if version
        if ns && !ns.empty?
          raise ArgumentError,
            "version: cannot be combined with namespace bindings " \
            "(the versioned engine entry takes no ns set yet)"
        end
        Leptris::XML::FFI.leptris_xpath_eval_versioned(
          doc_ptr, context_ptr, expr,
          Leptris::XML::Searchable.xpath_version_code(version), nil)
      elsif ns && !ns.empty?
        xpath_eval_with_namespaces(doc_ptr, context_ptr, expr, ns)
      elsif (compiled = Leptris::XML::Searchable.compiled_expression(expr))
        compiled.eval_ptrs(doc_ptr, context_ptr)
      else
        Leptris::XML::FFI.leptris_xpath_eval(doc_ptr, context_ptr, expr)
      end
    if result_ptr.null?
      raise Leptris::XML::XPathError,
        Leptris::XML::FFI.leptris_last_error.to_s
    end
    Leptris::XML::Searchable.wrap_xpath_first_result(document, result_ptr)
  end

  def search(*args)
    paths = args.first.is_a?(Array) ? args.first : [args.first]
    paths.map(&:to_s).all? { |p| looks_like_xpath?(p) } ? xpath(*paths) : css(*paths)
  end
  alias_method :/, :search

  # Single-node seam (round XIV): dispatch on syntax like #search,
  # then call the at_* fast paths directly — no NodeSet container,
  # no result handle, one fewer dispatch than search().first.
  def at(*args)
    paths = args.first.is_a?(Array) ? args.first : [args.first]
    if paths.map(&:to_s).all? { |p| looks_like_xpath?(p) }
      at_xpath(*paths)
    else
      at_css(*args)
    end
  end
  alias_method :%, :at

  def css(*args)
    handler, ns, version = parse_search_args(args)
    raise ArgumentError, "namespace bindings not supported in css" if ns && !ns.empty?
    raise ArgumentError, "version: is XPath-only" if version
    raise ArgumentError, "custom CSS handlers not supported" if handler
    # Nokogiri semantics: css is receiver-relative — absolute "//"
    # from a Document, descendant ".//" from elements and fragments.
    prefix = is_a?(Leptris::XML::Document) ? "//" : ".//"
    expr = args.map { |r| Leptris::XML::CssToXPath.convert(r, prefix: prefix) }
      .join(" | ")
    xpath(expr)
  end

  def at_css(*args)
    handler, ns, version = parse_search_args(args)
    raise ArgumentError, "namespace bindings not supported in css" if ns && !ns.empty?
    raise ArgumentError, "version: is XPath-only" if version
    raise ArgumentError, "custom CSS handlers not supported" if handler
    prefix = is_a?(Leptris::XML::Document) ? "//" : ".//"
    expr = args.map { |r| Leptris::XML::CssToXPath.convert(r, prefix: prefix) }
      .join(" | ")
    at_xpath(expr)
  end

  # Version-pinned evaluation (libleptris lane 15,
  # leptris_xpath_eval_versioned): :xpath10 keeps the strict XPath
  # 1.0 surface — 3.x syntax (arrow, bang, lookup, let, inline
  # functions, string templates) raises; :xpath31 evaluates the
  # full grammar (identical to #xpath's default entry). A separate
  # method by design: #xpath's trailing-hash argument is the
  # namespace-binding channel, and a declared keyword would
  # capture it.
  def xpath_versioned(expression, version)
    doc_ptr = is_a?(Leptris::XML::Document) ? c_ptr : document.c_ptr
    context_ptr = is_a?(Leptris::XML::Document) ? nil : c_ptr
    result_ptr = Leptris::XML::FFI.leptris_xpath_eval_versioned(
      doc_ptr, context_ptr, expression,
      Leptris::XML::Searchable.xpath_version_code(version), nil)
    if result_ptr.null?
      raise Leptris::XML::XPathError,
        Leptris::XML::FFI.leptris_last_error.to_s
    end
    Leptris::XML::Searchable.wrap_xpath_result(document, result_ptr)
  end

  protected

  # Evaluates against a caller-owned namespace binding set; the
  # build/teardown lifecycle lives at the FFI seam (FFI.with_ns_set).
  def xpath_eval_with_namespaces(doc_ptr, context_ptr, expr, ns)
    Leptris::XML::FFI.with_ns_set(ns) do |set|
      Leptris::XML::FFI.leptris_xpath_eval_ns(doc_ptr, context_ptr, expr, set)
    end
  end


  # Version pin for xpath_versioned: :xpath10
  # keeps the strict XPath 1.0 surface (3.x syntax — arrow, bang,
  # lookup, let, inline functions — raises); :xpath31 evaluates the
  # full grammar (identical to the default entry).
  def self.xpath_version_code(version)
    case version
    when :xpath10, "1.0" then Leptris::XML::FFI::XPATH_10
    when :xpath31, "3.1" then Leptris::XML::FFI::XPATH_31
    else
      raise ArgumentError,
        "version must be :xpath10 or :xpath31, got #{version.inspect}"
    end
  end

  # Trailing-argument contract (#183): a String-keyed hash is the
  # namespace-binding channel — as is a Symbol-keyed hash (the
  # legacy prefix vocabulary, {x: "urn:x"}); a :version key whose
  # VALUE is a version selector is the version-selection channel
  # (xpath("//b", version: "1.0"), mirroring leptris-py#105). A
  # DECLARED keyword cannot carry this: the moment #xpath declares
  # one, Ruby converts the trailing namespace hash into keywords
  # (unknown keyword: "p") — so both channels stay positional and
  # dispatch on key/value here.
  def parse_search_args(args)
    handler = args.find { |a| !a.is_a?(String) && !a.is_a?(Hash) && !a.is_a?(Symbol) }
    args = args - [handler] if handler
    hashes = []
    while args.last.is_a?(Hash) || args.last.nil?
      hashes << args.pop
      break if args.empty?
    end
    ns, vars = hashes.reverse
    unless vars.nil? || vars.empty?
      raise ArgumentError, "XPath variable bindings are not supported"
    end
    # Value-based disambiguation is load-bearing: Symbol keys are
    # also the namespace vocabulary, and bare keywords FUSE into a
    # preceding String-keyed hash at the call site ({"p" => uri,
    # version: "1.0"} arrives as ONE hash). A :version key with any
    # other value stays a prefix binding.
    version = nil
    if ns.is_a?(Hash)
      v = ns[:version]
      if VERSION_SELECTORS.include?(v)
        version = ns.delete(:version)
        ns = nil if ns.empty?
      elsif v.is_a?(String) && v.match?(/\A\d+\.\d+\z/)
        # A dotted-number :version value is version INTENT — raise
        # with the valid values rather than silently binding a
        # prefix literally. Genuine prefix bindings carry URIs.
        raise ArgumentError,
          "unknown XPath version #{v.inspect} " \
          "(valid: \"1.0\"/:xpath10, \"3.1\"/:xpath31)"
      end
    end
    [handler, ns, version]
  end

  def looks_like_xpath?(str)
    %r{\A(\./|/|\.\.|\.)}.match?(str)
  end

  # Single-node seam beside wrap_xpath_result: a nodeset answers
  # via result_get_node(0) + wrap + free — no NodeSet container, no
  # AutoPointer, one fewer FFI than xpath().first; scalars keep the
  # full-wrapper semantics.
  def self.wrap_xpath_first_result(document, result_ptr)
    type = Leptris::XML::FFI.leptris_xpath_result_type(result_ptr)
    if type == Leptris::XML::FFI::XPATH_NODESET
      ptr = Leptris::XML::FFI.leptris_xpath_result_get_node(result_ptr, 0)
      if ptr.null?
        node = nil
      else
        kind = Leptris::XML::FFI.leptris_xpath_result_node_kind(result_ptr, 0)
        node = if kind == Leptris::XML::FFI::XPATH_NODE_ATTRIBUTE
                 Leptris::XML::ResultAttr.new(
                   ptr, document,
                   Leptris::XML::FFI.leptris_xpath_result_node_name(result_ptr, 0),
                   Leptris::XML::FFI.leptris_xpath_result_node_value(result_ptr, 0))
               else
                 Leptris::XML::Node.wrap(ptr, document)
               end
      end
      Leptris::XML::FFI.leptris_xpath_result_free(result_ptr)
      node
    else
      wrap_xpath_result(document, result_ptr)
    end
  end

  # Shared by Searchable#xpath and Leptris::XML::XPath (compiled
  # expressions): wraps a raw XPathResult pointer into the
  # Ruby-typed result and frees the C handle.
  def self.wrap_xpath_result(document, result_ptr)
    type = Leptris::XML::FFI.leptris_xpath_result_type(result_ptr)
    case type
    when Leptris::XML::FFI::XPATH_NODESET
      Leptris::XML::NodeSet.from_result(document, result_ptr)
    when Leptris::XML::FFI::XPATH_BOOLEAN
      v = Leptris::XML::FFI.leptris_xpath_result_boolean(result_ptr) != 0
      Leptris::XML::FFI.leptris_xpath_result_free(result_ptr)
      v
    when Leptris::XML::FFI::XPATH_NUMBER
      v = Leptris::XML::FFI.leptris_xpath_result_number(result_ptr)
      Leptris::XML::FFI.leptris_xpath_result_free(result_ptr)
      v
    when Leptris::XML::FFI::XPATH_STRING
      str_ptr = Leptris::XML::FFI.leptris_xpath_result_string(result_ptr)
      v = Leptris::XML::FFI.read_owned_string(str_ptr)
      Leptris::XML::FFI.leptris_xpath_result_free(result_ptr)
      v
    when Leptris::XML::FFI::XPATH_FUNCTION
      Leptris::XML::FFI.leptris_xpath_result_free(result_ptr)
      raise Leptris::XML::XPathError,
            'XPath function items cannot cross the FFI boundary yet ' \
            '(libleptris TODO 07; call them inside the expression, ' \
            'e.g. for-each((1,2), function($n){$n+1}))'
    else
      Leptris::XML::FFI.leptris_xpath_result_free(result_ptr)
      raise Leptris::XML::XPathError, "unknown xpath result type #{type}"
    end
  end
end
