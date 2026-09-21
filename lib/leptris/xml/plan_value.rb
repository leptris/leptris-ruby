# frozen_string_literal: true

require "ffi"

# One node of a Descriptor#walk result (libleptris 1.9.162, upstream
# #1039): a lazy view over the engine-owned value tree. The ROOT
# value owns the whole-result handle (freed by GC); child values
# borrow from their parent — #at returns borrowed views, so the
# root must outlive them (hold the root, read freely).
#
# The C result API reads attributes BY NAME only, so element
# attribute enumeration threads the producing plan's attribute
# rows: Descriptor#walk plants the root plan, #to_ruby walks
# (value, plan) pairs in parallel.
class Leptris::XML::PlanValue
  VALUE_KINDS = {
    Leptris::XML::FFI::PLAN_VALUE_ELEMENT => :element,
    Leptris::XML::FFI::PLAN_VALUE_SCALAR => :scalar,
    Leptris::XML::FFI::PLAN_VALUE_COLLECTION => :collection,
    Leptris::XML::FFI::PLAN_VALUE_RAW => :raw,
    Leptris::XML::FFI::PLAN_VALUE_CALLBACK => :callback,
  }.freeze
  private_constant :VALUE_KINDS

  def initialize(ptr, owner: nil, plans: nil, plan: nil, counter: nil)
    @ptr = ptr
    @owner = owner
    @plans = plans
    @plan = plan
    @counter = counter || [0]
  end

  def kind
    inc_crossing
    VALUE_KINDS.fetch(Leptris::XML::FFI.leptris_plan_value_kind(@ptr))
  end

  # wire_name of the plan row that produced this value.
  def name
    inc_crossing
    Leptris::XML::FFI.leptris_plan_value_name(@ptr)
  end

  # Host type_tag echoed verbatim (0 when the row had none).
  def type_tag
    inc_crossing
    Leptris::XML::FFI.leptris_plan_value_type_tag(@ptr)
  end

  # #1273: LEPTRIS_NODE_TYPE_* of this value's source node (0 for
  # ELEMENT/COLLECTION wrappers and synthesized text).
  def node_kind
    inc_crossing
    Leptris::XML::FFI.leptris_plan_value_node_kind(@ptr)
  end

  # #1273: dense sibling rank inside the producing element (0 if
  # unranked) — document-order identity without byte offsets.
  def order_index
    inc_crossing
    Leptris::XML::FFI.leptris_plan_value_order_index(@ptr)
  end

  # #1269a: the walk parsed type_tag ∈ {1,2,3} values natively.
  # Returns the typed value, or nil when the row's tag isn't a
  # typed one or the source text didn't parse (host falls back to
  # #string_value / the lenient Ruby path).
  def int_value
    out = ::FFI::MemoryPointer.new(:int64)
    return nil unless Leptris::XML::FFI.leptris_plan_value_int(@ptr, out).zero?
    out.read_int64
  end

  def float_value
    out = ::FFI::MemoryPointer.new(:double)
    return nil unless Leptris::XML::FFI.leptris_plan_value_float(@ptr, out).zero?
    out.read_double
  end

  def bool_value
    out = ::FFI::MemoryPointer.new(:int)
    return nil unless Leptris::XML::FFI.leptris_plan_value_bool(@ptr, out).zero?
    out.read_int != 0
  end

  # SCALAR / RAW / CALLBACK string value.
  def string_value
    inc_crossing
    Leptris::XML::FFI.leptris_plan_value_string(@ptr)
  end

  # CALLBACK: document byte offset of the source node (0 unknown).
  def position
    inc_crossing
    Leptris::XML::FFI.leptris_plan_value_position(@ptr)
  end

  # ELEMENT: child-value count. COLLECTION: item count.
  def count
    inc_crossing
    Leptris::XML::FFI.leptris_plan_value_count(@ptr)
  end

  # ELEMENT child value / COLLECTION item at +i+ (nil out of
  # range). Borrowed: the owning root must stay alive.
  def at(i)
    inc_crossing
    ptr = Leptris::XML::FFI.leptris_plan_value_at(@ptr, i)
    return nil if ptr.null?
    child_plan = child_plan_for_position(ptr)
    Leptris::XML::PlanValue.new(ptr, plans: @plans, plan: child_plan,
                                    counter: @counter)
  end

  # ELEMENT: attribute value by wire_name (nil when absent).
  def attribute(wire_name)
    inc_crossing
    Leptris::XML::FFI.leptris_plan_value_attribute(@ptr, wire_name.to_s)
  end

  # The number of FFI accessor calls this PlanValue (and its
  # #as_kwarg_hash descendants, via the borrowed-#at chain) have
  # counted. Reset with #reset_crossings! before the work you want
  # to count. Counts FFI crossings only — engine-internal walks
  # during `leptris_plan_walk` are not exposed (they belong to
  # leptris/leptris#1269's headroom).
  def crossings
    @counter[0]
  end

  def reset_crossings!
    @counter[0] = 0
    self
  end

  # Bulk kwarg view (#298's binding ask): one Ruby method yields
  # the hash the consumer's hydrator wants per row — no per-field
  # dispatch on the hot path. Honors the row type tags (typed
  # scalars and collected attributes; the nested rows recurse via
  # the same face so the whole row-graph collapses into one Ruby
  # method call per node).
  #
  #   { name:, type_tag:,
  #     attributes: { wire_name => typed_value, ... },
  #     children:   { wire_name => typed_value | [typed_value, ...] } }
  #
  # The +name+ is the element wire_name (nil on the root, by
  # engine contract); +type_tag+ echoes the plan row's type tag
  # (0 when absent). Collection rows appear as Arrays; callbacks
  # are emitted as +{value:, position:, type_tag:}+ like #to_ruby.
  def as_kwarg_hash
    inc_crossing # the kind probe + name + type_tag are one logical fetch
    case kind
    when :element
      {
        name: name,
        type_tag: type_tag,
        attributes: kwarg_attributes,
        children: kwarg_children,
      }
    when :collection
      kwarg_collection_children
    when :callback
      { value: string_value, position: position, type_tag: type_tag }
    else
      typed_string_value
    end
  end

  # The eager Ruby tree:
  #   :element    => { kind:, name:, type_tag:, attributes: {...},
  #                   children: [values] }
  #   :scalar/:raw => String
  #   :collection => [values]
  #   :callback   => { value:, position:, type_tag: }
  def to_ruby
    case kind
    when :element
      {
        kind: :element,
        name: name,
        type_tag: type_tag,
        attributes: collected_attributes,
        children: Array.new(count) { |i| at(i).to_ruby },
      }
    when :collection
      Array.new(count) { |i| at(i).to_ruby }
    when :callback
      { value: string_value, position: position, type_tag: type_tag }
    else
      typed_string_value
    end
  end

  private

  def inc_crossing
    @counter[0] += 1
  end

  def kwarg_attributes
    ((@plan && @plan[:attributes]) || []).each_with_object({}) do |row, result|
      v = attribute(row[:name])
      result[row[:name]] = cast_attribute(v, row) unless v.nil?
    end
  end

  def kwarg_children
    rows = ((@plan && @plan[:children]) || [])
    result = {}
    rows.each_with_index do |row, i|
      value = at(i)
      next if value.nil?
      key = row[:name]
      coerced = coerce_kwarg(value, row[:kind])
      result[key] = if result.key?(key)
        Array(result[key]) << coerced
      else
        coerced
      end
    end
    result
  end

  def kwarg_collection_children
    Array.new(count) { |i| coerce_kwarg(at(i)) }
  end

  # Coerce a PlanValue row to the shape the consumer's hydrator
  # wants: scalars/ra→raw/callback collapse to typed values;
  # :element children recurse into the kwarg hash; :collection
  # children yield the array of typed items.
  def coerce_kwarg(value, kind = nil)
    v_kind = kind || value.kind
    case v_kind
    when :element then value.as_kwarg_hash
    when :collection then Array.new(value.count) { |i| coerce_kwarg(value.at(i)) }
    when :callback
      { value: value.string_value, position: value.position,
        type_tag: value.type_tag }
    else
      typed_string_value_for(value)
    end
  end

  def typed_string_value_for(value)
    case value.type_tag
    when 1 then value.int_value || (Integer(value.string_value, 10) rescue value.string_value)
    when 2 then value.float_value || (Float(value.string_value) rescue value.string_value)
    when 3
      v = value.bool_value
      v.nil? ? typed_bool_fallback(value.string_value) : v
    else value.string_value
    end
  end
  # contract): 1=Integer, 2=Float, 3=boolean. Executed in-pass by
  # the engine (#1269a); on its soft-fail (non-numeric source) the
  # lenient Ruby path applies, then the raw String wins.
  # #string_value stays the raw escape.
  def typed_string_value
    case type_tag
    when 1
      int_value || (string_value && (Integer(string_value, 10) rescue string_value))
    when 2
      float_value || (string_value && (Float(string_value) rescue string_value))
    when 3
      v = bool_value
      v.nil? ? typed_bool_fallback(string_value) : v
    else
      string_value
    end
  end

  def typed_bool_fallback(s)
    case s
    when "true", "1" then true
    when "false", "0" then false
    else s
    end
  end

  # The element plan that the child value +ptr+ recurses into (nil
  # for non-nested rows — their values carry no plan). Fast path:
  # with exactly ONE child row, every matched value must be that
  # row — the FFI name probe is skipped (#298 crossings floor).
  # Multi-row plans probe by wire_name (result positions only
  # cover matched children, so positional mapping is unsafe).
  def child_plan_for_position(ptr)
    return nil unless @plan
    rows = @plan[:children] || []
    row = rows.size == 1 ? rows.first : nil
    unless row
      inc_crossing
      child_name = Leptris::XML::FFI.leptris_plan_value_name(ptr)
      row = rows.find { |r| r[:name] == child_name }
    end
    return nil unless row && @plans
    row[:kind] == :nested ? @plans[row[:child_plan_index]] : nil
  end

  def child_row_plan(child_wire_name)
    row = (@plan[:children] || []).find do |r|
      r[:kind] == :nested && r[:name] == child_wire_name
    end
    return nil unless row && @plans
    @plans[row[:child_plan_index]]
  end

  def collected_attributes
    result = {}
    ((@plan && @plan[:attributes]) || []).each do |row|
      v = attribute(row[:name])
      result[row[:name]] = cast_attribute(v, row) unless v.nil?
    end
    result
  end

  # Attribute values come back as plain Strings from the walk;
  # apply the row's type tag with the same lenient semantics as
  # typed_string_value.
  def cast_attribute(value, row)
    tag = Leptris::XML::Descriptor.type_tag_code(row)
    case tag
    when 1 then Integer(value, 10) rescue value
    when 2
      begin
        Float(value)
      rescue ArgumentError, TypeError
        value
      end
    when 3
      case value
      when "true", "1" then true
      when "false", "0" then false
      else value
      end
    else value
    end
  end
end
