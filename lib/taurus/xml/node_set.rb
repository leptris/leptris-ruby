# frozen_string_literal: true

class Taurus::XML::NodeSet
  include Enumerable
  include Taurus::XML::Searchable

  attr_reader :document

  def initialize(document, array = [])
    @document = document
    @array = array.to_a
  end

  def self.from_result(document, result_ptr)
    n = Taurus::XML::FFI.taurus_xpath_result_count(result_ptr)
    nodes = n.times.map do |i|
      ptr = Taurus::XML::FFI.taurus_xpath_result_get(result_ptr, i)
      next nil if ptr.null?
      Taurus::XML::Node.wrap(ptr, document)
    end.compact
    Taurus::XML::FFI.taurus_xpath_result_free(result_ptr)
    new(document, nodes)
  end

  def each
    return enum_for(:each) unless block_given?
    @array.each { |n| yield n }
    self
  end

  def [](idx); @array[idx]; end
  def length;  @array.length; end
  alias_method :size, :length
  def empty?;  @array.empty?; end
  def first(n = nil); n.nil? ? @array.first : @array.first(n); end
  def last;    @array.last; end
  def to_a;    @array.dup; end
  def to_ary;  @array; end

  def inner_text
    @array.map(&:content).join
  end
  alias_method :text, :inner_text

  def xpath(*paths)
    handler, _ns, _vars = parse_search_args(paths)
    raise ArgumentError, "custom XPath handlers not supported" if handler
    expr = paths.join(" | ")
    accumulated = Taurus::XML::NodeSet.new(@document)
    @array.each do |node|
      next unless node.is_a?(Taurus::XML::Element)
      result_ptr = Taurus::XML::FFI.taurus_xpath_eval(
        @document.c_ptr, node.c_ptr, expr)
      next if result_ptr.null?
      sub = Taurus::XML::NodeSet.send(:from_result, @document, result_ptr)
      accumulated = merge_node_sets(accumulated, sub)
    end
    accumulated
  end

  def inspect
    "[#{@array.map(&:inspect).join(", ")}]"
  end

  private

  def merge_node_sets(a, b)
    Taurus::XML::NodeSet.new(@document, a.to_a + b.to_a)
  end
end
