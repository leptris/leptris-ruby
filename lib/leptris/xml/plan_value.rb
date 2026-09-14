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

  def initialize(ptr, owner: nil, plans: nil, plan: nil)
    @ptr = ptr
    @owner = owner
    @plans = plans
    @plan = plan
  end

  def kind
    VALUE_KINDS.fetch(Leptris::XML::FFI.leptris_plan_value_kind(@ptr))
  end

  # wire_name of the plan row that produced this value.
  def name
    Leptris::XML::FFI.leptris_plan_value_name(@ptr)
  end

  # Host type_tag echoed verbatim (0 when the row had none).
  def type_tag
    Leptris::XML::FFI.leptris_plan_value_type_tag(@ptr)
  end

  # SCALAR / RAW / CALLBACK string value.
  def string_value
    Leptris::XML::FFI.leptris_plan_value_string(@ptr)
  end

  # CALLBACK: document byte offset of the source node (0 unknown).
  def position
    Leptris::XML::FFI.leptris_plan_value_position(@ptr)
  end

  # ELEMENT: child-value count. COLLECTION: item count.
  def count
    Leptris::XML::FFI.leptris_plan_value_count(@ptr)
  end

  # ELEMENT child value / COLLECTION item at +i+ (nil out of
  # range). Borrowed: the owning root must stay alive.
  def at(i)
    ptr = Leptris::XML::FFI.leptris_plan_value_at(@ptr, i)
    return nil if ptr.null?
    child_name = Leptris::XML::FFI.leptris_plan_value_name(ptr)
    child_plan = @plan ? child_row_plan(child_name) : nil
    Leptris::XML::PlanValue.new(ptr, plans: @plans, plan: child_plan)
  end

  # ELEMENT: attribute value by wire_name (nil when absent).
  def attribute(wire_name)
    Leptris::XML::FFI.leptris_plan_value_attribute(@ptr, wire_name.to_s)
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
      string_value
    end
  end

  private

  # The element plan that a child row with this wire_name recurses
  # into (nil for non-nested rows — their values carry no plan).
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
      result[row[:name]] = v unless v.nil?
    end
    result
  end
end
