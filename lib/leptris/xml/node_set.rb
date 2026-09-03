# frozen_string_literal: true

require "ffi"

class Leptris::XML::NodeSet
  include Enumerable
  include Leptris::XML::Searchable

  attr_reader :document

  # Two construction modes:
  # - eager: pass an Array of Nodes (e.g. Element#children builds one)
  # - lazy:  pass an FFI::Pointer to a LeptrisXPathResult that this NodeSet
  #          will keep alive and free on GC. Each [i] / each call goes
  #          through leptris_xpath_result_get instead of pre-materializing.
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
        @result_ptr = ::FFI::AutoPointer.new(source, Leptris::XML::FFI.method(:leptris_xpath_result_free))
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
    return @array.length if @array
    @result_ptr ? Leptris::XML::FFI.leptris_xpath_result_count(@result_ptr) : 0
  end
  alias_method :size, :length

  def empty?
    length == 0
  end

  # The materialized array (after to_a) is authoritative: every
  # reader consults it first so a materialized set stops paying the
  # batch fetch on each iteration or index.
  def [](idx)
    return @array[idx] if @array
    # Negative indexes are Ruby-Array semantics (Nokogiri's NodeSet
    # is slice-like); materialize rather than answer nil
    # inconsistently with an eager set.
    return to_a[idx] if idx.negative?
    if @result_ptr
      ptr = Leptris::XML::FFI.leptris_xpath_result_get_node(@result_ptr, idx)
      return nil if ptr.null?
      Leptris::XML::Node.wrap(
        ptr, @document,
        result_value: text_item_value(
          Leptris::XML::FFI.leptris_xpath_result_node_kind(@result_ptr, idx), idx))
    end
  end

  # Sequence/map/array items ride synthetic text nodes whose value
  # only the live result handle can serve — capture it now.
  def text_item_value(kind, index)
    return nil unless kind == Leptris::XML::FFI::XPATH_NODE_TEXT
    Leptris::XML::FFI.leptris_xpath_result_node_value(@result_ptr, index)
  end
  private :text_item_value

  # Iteration materializes: the first pass batch-fetches into @array
  # (yielding as it wraps), and every subsequent reader — each, [],
  # length — serves from the array. Repeated iteration without an
  # explicit to_a pays the batch exactly once.
  def each
    return enum_for(:each) unless block_given?
    unless @array
      return self unless @result_ptr
      n = length
      if n > 0
        # Batch-fetch all node pointers through the FFI seam
        # (leptris_xpath_result_get_nodes_ex copies every node kind,
        # not just elements); the batch accessor under-copies
        # mixed-kind results (upstream leptris#477), so per-index
        # fetch covers the remainder.
        pointers, kinds, raw = Leptris::XML::FFI.fetch_result_nodes(@result_ptr, n)
        nodes = []
        pointers.each_with_index do |ptr, i|
          next if ptr.null?
          nodes << Leptris::XML::Node.wrap(
            ptr, @document, node_type: kinds[i],
            result_value: text_item_value(raw[i], i))
        end
        (pointers.length...n).each do |i|
          ptr = Leptris::XML::FFI.leptris_xpath_result_get_node(@result_ptr, i)
          next if ptr.null?
          nodes << Leptris::XML::Node.wrap(
            ptr, @document,
            result_value: text_item_value(
              Leptris::XML::FFI.leptris_xpath_result_node_kind(@result_ptr, i), i))
        end
        @array = nodes
      else
        @array = []
      end
    end
    @array.each { |n| yield n }
    self
  end

  def to_a
    return @array if @array
    return [] if @result_ptr.nil?
    each { |n| }  # materializes @array as a side effect
    @array
  end
  alias_method :to_ary, :to_a

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

  def inner_text
    map(&:content).join
  end
  alias_method :text, :inner_text

  # Union semantics: ONE engine call evaluates the expression
  # against every element member and merges the results into a
  # de-duplicated, document-ordered nodeset (libleptris 1.9.7,
  # upstream #589 — the per-member Ruby loop this replaces could
  # neither dedup nor order).
  def xpath(*paths)
    handler, _ns, _vars = parse_search_args(paths)
    raise ArgumentError, "custom XPath handlers not supported" if handler
    expr = paths.join(" | ")
    contexts = to_a.select { |node| node.is_a?(Leptris::XML::Element) }
    return Leptris::XML::NodeSet.new(@document, []) if contexts.empty?
    buffer = Leptris::XML::FFI.scratch_pointers(contexts.size)
    buffer.write_array_of_pointer(contexts.map(&:c_ptr))
    result_ptr = Leptris::XML::FFI.leptris_xpath_eval_nodeset(
      @document.c_ptr, buffer, contexts.size, expr)
    return Leptris::XML::NodeSet.new(@document, []) if result_ptr.null?
    Leptris::XML::NodeSet.from_result(@document, result_ptr)
  end

  def inspect
    to_a.inspect
  end
end
