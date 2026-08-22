# frozen_string_literal: true

module Leptris::XML::Searchable
  def xpath(*paths)
    handler, _ns, _vars = parse_search_args(paths)
    raise ArgumentError, "custom XPath handlers not supported" if handler
    expr = paths.join(" | ")

    doc_ptr = is_a?(Leptris::XML::Document) ? c_ptr : document.c_ptr
    context_ptr = is_a?(Leptris::XML::Document) ? nil : c_ptr

    result_ptr = Leptris::XML::FFI.leptris_xpath_eval(doc_ptr, context_ptr, expr)
    if result_ptr.null?
      raise Leptris::XML::XPathError,
        Leptris::XML::FFI.leptris_status_string(Leptris::XML::FFI::LEPTRIS_ERROR_XPATH)
    end

    wrap_xpath_result(result_ptr)
  end

  def at_xpath(*paths)
    result = xpath(*paths)
    result.is_a?(Leptris::XML::NodeSet) ? result.first : result
  end

  def search(*args)
    paths = args.first.is_a?(Array) ? args.first : [args.first]
    paths.map(&:to_s).all? { |p| looks_like_xpath?(p) } ? xpath(*paths) : css(*paths)
  end
  alias_method :/, :search

  def at(*args)
    result = search(*args)
    result.is_a?(Leptris::XML::NodeSet) ? result.first : result
  end
  alias_method :%, :at

  def css(*args)
    handler, ns, _ = parse_search_args(args)
    raise ArgumentError, "namespace bindings not supported in css" if ns && !ns.empty?
    raise ArgumentError, "custom CSS handlers not supported" if handler
    expr = args.map { |r| Leptris::XML::CssToXPath.convert(r) }.join(" | ")
    xpath(expr)
  end

  def at_css(*args)
    result = css(*args)
    result.is_a?(Leptris::XML::NodeSet) ? result.first : result
  end

  protected

  def parse_search_args(args)
    handler = args.find { |a| !a.is_a?(String) && !a.is_a?(Hash) && !a.is_a?(Symbol) }
    args = args - [handler] if handler
    hashes = []
    while args.last.is_a?(Hash) || args.last.nil?
      hashes << args.pop
      break if args.empty?
    end
    ns, vars = hashes.reverse
    [handler, ns, vars]
  end

  def looks_like_xpath?(str)
    %r{\A(\./|/|\.\.|\.)}.match?(str)
  end

  def wrap_xpath_result(result_ptr)
    type = Leptris::XML::FFI.leptris_xpath_result_type(result_ptr)
    case type
    when Leptris::XML::FFI::XPATH_NODESET
      Leptris::XML::NodeSet.send(:from_result, document, result_ptr)
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
    else
      Leptris::XML::FFI.leptris_xpath_result_free(result_ptr)
      raise Leptris::XML::XPathError, "unknown xpath result type #{type}"
    end
  end
end
