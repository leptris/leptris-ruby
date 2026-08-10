# frozen_string_literal: true

require "ffi"

class Taurus::XML::NodeSet
  include Enumerable
  include Taurus::XML::Searchable

  attr_reader :document

  # Two construction modes:
  # - eager: pass an Array of Nodes (e.g. Element#children builds one)
  # - lazy:  pass an FFI::Pointer to a TaurusXPathResult that this NodeSet
  #          will keep alive and free on GC. Each [i] / each call goes
  #          through taurus_xpath_result_get instead of pre-materializing.
  def initialize(document, source = nil)
    @document = document
    case source
    when ::FFI::Pointer
      if source.null?
        @result_ptr = nil
        @array = []
      else
        # Wrap in AutoPointer for automatic GC-time cleanup. NodeSet has no
        # explicit #free method (Nokogiri doesn't either), so the AutoPointer
        # double-free risk that Document#free hit doesn't apply here.
        @result_ptr = ::FFI::AutoPointer.new(source, Taurus::XML::FFI.method(:taurus_xpath_result_free))
        @array = nil
      end
    when nil
      @result_ptr = nil
      @array = []
    else
      @result_ptr = nil
      @array = source.to_a
    end
  end

  def self.from_result(document, result_ptr)
    new(document, result_ptr)
  end

  def length
    @result_ptr ? Taurus::XML::FFI.taurus_xpath_result_count(@result_ptr) : @array.length
  end
  alias_method :size, :length

  def empty?
    length == 0
  end

  def [](idx)
    if @result_ptr
      return nil if idx < 0 || idx >= length
      ptr = Taurus::XML::FFI.taurus_xpath_result_get(@result_ptr, idx)
      return nil if ptr.null?
      Taurus::XML::Node.wrap(ptr, @document)
    else
      @array[idx]
    end
  end

  def each
    return enum_for(:each) unless block_given?
    if @result_ptr
      length.times { |i| yield self[i] }
    else
      @array.each { |n| yield n }
    end
    self
  end

  def first(n = nil)
    return self[0] if n.nil?
    n.times.map { |i| self[i] }.take_while { |x| !x.nil? }
  end

  def last
    if @result_ptr
      self[length - 1]
    else
      @array.last
    end
  end

  def to_a
    @array || length.times.map { |i| self[i] }
  end
  alias_method :to_ary, :to_a

  def inner_text
    map(&:content).join
  end
  alias_method :text, :inner_text

  def xpath(*paths)
    handler, _ns, _vars = parse_search_args(paths)
    raise ArgumentError, "custom XPath handlers not supported" if handler
    expr = paths.join(" | ")
    accumulated = Taurus::XML::NodeSet.new(@document)
    each do |node|
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
    to_a.inspect
  end

  private

  def merge_node_sets(a, b)
    Taurus::XML::NodeSet.new(@document, a.to_a + b.to_a)
  end
end
