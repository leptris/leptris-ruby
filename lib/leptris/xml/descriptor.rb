# frozen_string_literal: true

require "ffi"

# Tree-shaped schema-descriptor materialization (libleptris 1.9.162,
# upstream #1039): compile a plan tree once, then materialize a whole
# subtree against it in ONE native pass — no per-element Ruby calls
# (#185's class of cost). Children the plan does not describe are
# skipped; matches within a row keep document order.
#
#     descriptor = Leptris::XML::Descriptor.build(
#       name: "catalog",
#       attributes: [{ name: "version", kind: :scalar }],
#       children: [
#         { name: "item", kind: :nested, plan: {
#             name: "item",
#             attributes: [{ name: "id", kind: :scalar }],
#             children: [
#               { name: "name", kind: :scalar },
#               { name: "price", kind: :scalar },
#             ] } },
#       ])
#     descriptor.walk(doc.root).to_ruby
#
# Plan rows: :scalar, :collection (repeated matches), :nested (recurse
# via +plan:+), :raw (serialized subtree), :content (mixed-content
# text runs), :callback (raw value + byte position + type_tag echo).
# Namespace binding per plan: +ns:+ is :none (default), :any, or
# { exact: "urn:..." }; +flags: [:mixed_content, :ordered, :cdata,
# :ns_lenient].
#
# == Typed scalars (#230's fused-consumer contract, mirroring the
# yeptris schema ABI)
#
# Attribute and child rows accept +type: :string (default),
# :integer, :float, or :boolean+. The tag travels through the plan
# ABI (host-defined, echoed verbatim) and PlanValue#to_ruby returns
# the cast value — Integer / Float / true / false — so per-value
# cast probes disappear from the consumer. Unparseable values fall
# back to the raw String (lenient, first-wins house style);
# #string_value always returns the raw String regardless of tag.
#
#     descriptor = Leptris::XML::Descriptor.build(
#       name: "catalog",
#       children: [
#         { name: "price", kind: :scalar, type: :float },
#         { name: "in_stock", kind: :scalar, type: :boolean },
#       ])
#     descriptor.materialize(xml_source).to_ruby  # typed, one call
class Leptris::XML::Descriptor
  TYPE_TAGS = {
    string: 0,
    integer: 1,
    float: 2,
    boolean: 3,
  }.freeze
  private_constant :TYPE_TAGS
  class Handle < ::FFI::AutoPointer
    def self.release(ptr)
      Leptris::XML::FFI.leptris_plan_free(ptr)
    end
  end

  class ResultHandle < ::FFI::AutoPointer
    def self.release(ptr)
      Leptris::XML::FFI.leptris_plan_result_free(ptr)
    end
  end

  KINDS = {
    scalar: Leptris::XML::FFI::PLAN_KIND_SCALAR,
    collection: Leptris::XML::FFI::PLAN_KIND_COLLECTION,
    nested: Leptris::XML::FFI::PLAN_KIND_NESTED,
    raw: Leptris::XML::FFI::PLAN_KIND_RAW,
    content: Leptris::XML::FFI::PLAN_KIND_CONTENT,
    callback: Leptris::XML::FFI::PLAN_KIND_CALLBACK,
  }.freeze
  private_constant :KINDS

  FLAGS = {
    mixed_content: Leptris::XML::FFI::PLAN_FLAG_MIXED_CONTENT,
    ordered: Leptris::XML::FFI::PLAN_FLAG_ORDERED,
    cdata: Leptris::XML::FFI::PLAN_FLAG_CDATA,
    ns_lenient: Leptris::XML::FFI::PLAN_FLAG_NS_LENIENT,
    # #1273: also emit unmatched sibling text runs / comments / PIs
    # as SCALAR values (position + node_kind populated) so ordered
    # hosts rebuild element_order without re-parsing the source.
    order_spine: Leptris::XML::FFI::PLAN_FLAG_EMIT_ORDER_SPINE,
  }.freeze
  private_constant :FLAGS

  attr_reader :root

  # +tree+ is the root plan (the hash shape documented on the
  # class). Returns the compiled, engine-owned descriptor; the
  # Ruby-side spec memory is transient (the engine deep-copies).
  def self.build(tree)
    abi = Leptris::XML::FFI.leptris_plan_abi_version
    if abi != Leptris::XML::FFI::PLAN_ABI_VERSION
      raise Leptris::XML::Error,
        "descriptor ABI v#{abi} != binding v#{Leptris::XML::FFI::PLAN_ABI_VERSION}"
    end
    plans = []
    root_index = flatten_plan(tree, plans)
    spec, plans_pointer, anchors = pack_plans(plans)
    spec[:abi_version] = abi
    spec[:plan_count] = plans.size
    spec[:plans] = plans_pointer
    status = ::FFI::MemoryPointer.new(:int)
    raw = Leptris::XML::FFI.leptris_plan_build(spec.pointer, status)
    if raw.null?
      raise Leptris::XML::Error,
        "plan build failed (status=#{status.read_int})"
    end
    new(Handle.new(raw), plans, root_index)
  end

  # Flattens the nested hash tree into the engine's flat plans
  # array (child rows reference plans by index). Returns the root
  # plan's index — always 0 for a single root.
  def self.flatten_plan(tree, plans)
    tree = tree.dup
    plans << tree
    tree_index = plans.size - 1
    tree[:children] = (tree[:children] || []).map do |row|
      if row[:kind] == :nested
        row.merge(child_plan_index: flatten_plan(row.fetch(:plan), plans))
      else
        row
      end
    end
    tree_index
  end
  private_class_method :flatten_plan

  # Packs the flattened plans into FFI memory: one ElementPlan per
  # plan plus one AttrPlan/ChildPlan row per attribute/child. Every
  # C string and row array is anchored in Ruby until the build call
  # returns (the engine deep-copies).
  def self.pack_plans(plans)
    anchors = [nil]
    plan_memory = ::FFI::MemoryPointer.new(
      Leptris::XML::FFI::ElementPlan, plans.size)
    anchors[0] = plan_memory
    plans.each_with_index do |plan, i|
      ep = Leptris::XML::FFI::ElementPlan.new(plan_memory[i])
      ep[:element_name] = anchor_string(anchors, plan.fetch(:name))
      ns = plan[:ns]
      ns_form, ns_uri =
        case ns
        when nil, :none then [Leptris::XML::FFI::PLAN_NS_NONE, nil]
        when :any then [Leptris::XML::FFI::PLAN_NS_ANY, nil]
        when Hash
          [Leptris::XML::FFI::PLAN_NS_EXACT,
           anchor_string(anchors, ns.fetch(:exact))]
        else
          raise ArgumentError, "ns must be :none, :any, or {exact: uri}"
        end
      ep[:ns_form] = ns_form
      ep[:ns_uri] = ns_uri
      attrs = plan[:attributes] || []
      attr_memory = attrs.empty? ? nil :
        ::FFI::MemoryPointer.new(Leptris::XML::FFI::AttrPlan, attrs.size)
      anchors << attr_memory
      attrs.each_with_index do |row, j|
        ap = Leptris::XML::FFI::AttrPlan.new(attr_memory[j])
        ap[:wire_name] = anchor_string(anchors, row.fetch(:name))
        ap[:kind] = kind_code(row[:kind] || :scalar)
        ap[:type_tag] = type_tag_code(row)
        pack_predicates(ap, row, anchors)
      end
      ep[:attribute_count] = attrs.size
      ep[:attribute_plans] = attr_memory
      children = plan[:children] || []
      child_memory = children.empty? ? nil :
        ::FFI::MemoryPointer.new(Leptris::XML::FFI::ChildPlan, children.size)
      anchors << child_memory
      children.each_with_index do |row, j|
        cp = Leptris::XML::FFI::ChildPlan.new(child_memory[j])
        cp[:wire_name] = anchor_string(anchors, row.fetch(:name))
        cp[:kind] = kind_code(row[:kind] || :scalar)
        cp[:type_tag] = type_tag_code(row)
        cp[:child_plan_index] = row[:child_plan_index] || -1
        # Rule-level ns form (libleptris 1.9.178, #1115): siblings
        # under one parent can require different URIs when set;
        # defaults to NONE for backward compatibility.
        cp[:ns_form] =
          case row[:ns]
          when :any then Leptris::XML::FFI::PLAN_NS_ANY
          when Hash  then Leptris::XML::FFI::PLAN_NS_EXACT
          else         Leptris::XML::FFI::PLAN_NS_NONE
          end
        cp[:ns_uri] =
          row[:ns].is_a?(Hash) ?
            anchor_string(anchors, row[:ns].fetch(:exact)) : nil
        pack_predicates(cp, row, anchors)
      end
      ep[:child_count] = children.size
      ep[:child_plans] = child_memory
      ep[:flags] = (plan[:flags] || []).map { |f| FLAGS.fetch(f) }.sum
    end
    [Leptris::XML::FFI::PlanSpec.new, plan_memory, anchors]
  end
  private_class_method :pack_plans

  # Anchors the NUL-terminated copy in +anchors+ — the engine
  # deep-copies at build, but the source bytes must live until the
  # leptris_plan_build call returns.
  def self.anchor_string(anchors, ruby_string)
    ptr = ::FFI::MemoryPointer.from_string(ruby_string.to_s)
    anchors << ptr
    ptr
  end
  private_class_method :anchor_string

  def self.kind_code(kind)
    KINDS.fetch(kind) do
      raise ArgumentError,
        "kind must be one of #{KINDS.keys.inspect}, got #{kind.inspect}"
    end
  end
  private_class_method :kind_code

  # +type: :string/:integer/:float/:boolean+ (or a raw numeric
  # type_tag passthrough for hosts with their own vocabulary).
  # Public: PlanValue's attribute casts share the vocabulary.
  def self.type_tag_code(row)
    if row.key?(:type)
      TYPE_TAGS.fetch(row[:type]) do
        raise ArgumentError,
          "type must be one of #{TYPE_TAGS.keys.inspect}, got #{row[:type].inspect}"
      end
    else
      row[:type_tag] || 0
    end
  end

  # #1272 attribute-predicate rows: +when:+ accepts
  # {attr => value} (AND across pairs) or [[attr, value], ...].
  # Same-wire-name rows with different predicates partition the
  # match space exclusively (first matching row wins per
  # occurrence). Nil expected values are rejected — the engine's
  # predicate is string-equal only.
  def self.pack_predicates(plan_struct, row, anchors)
    preds = row[:when] or return
    pairs = case preds
            when Hash then preds.to_a
            when Array then preds
            else raise ArgumentError,
              "when must be a Hash or an Array of [attr, value] pairs"
            end
    pairs.each do |(name, value)|
      raise ArgumentError, "when: expected values must be non-nil" if value.nil?
    end
    memory = ::FFI::MemoryPointer.new(
      Leptris::XML::FFI::AttrPredicate, pairs.size)
    anchors << memory
    pairs.each_with_index do |(name, value), k|
      pr = Leptris::XML::FFI::AttrPredicate.new(memory[k])
      pr[:wire_name] = anchor_string(anchors, name.to_s)
      pr[:expected_value] = anchor_string(anchors, value.to_s)
    end
    plan_struct[:predicate_count] = pairs.size
    plan_struct[:predicates] = pairs.empty? ? nil : memory
  end

  def initialize(handle, plans, root_index)
    @handle = handle
    @plans = plans
    @root_index = root_index
  end

  # Materializes the subtree rooted at +element_or_document+ (the
  # root plan applies to the context node itself) in one native
  # pass. Returns the lazy PlanValue tree — a standalone result
  # that outlives the document.
  def walk(element_or_document)
    context = Leptris::XML::EvaluationContext.of(element_or_document)
    status = ::FFI::MemoryPointer.new(:int)
    raw = Leptris::XML::FFI.leptris_plan_walk(
      context.document.c_ptr, context.context_node_ptr, @handle, status)
    if raw.null?
      raise Leptris::XML::Error,
        "plan walk failed (status=#{status.read_int})"
    end
    Leptris::XML::PlanValue.new(ResultHandle.new(raw),
                                owner: true, plans: @plans, plan: @plans[0])
  end

  # The fused loop (#1269b): source bytes → typed rows in ONE C
  # call — leptris_plan_materialize runs parse, walk, and free
  # natively; the returned PlanValue tree is standalone and the
  # Document never exists. Byte-parity with #walk on the source's
  # root element.
  def materialize(source)
    s = source.to_s
    status = ::FFI::MemoryPointer.new(:int)
    raw = Leptris::XML::FFI.leptris_plan_materialize(
      s, s.bytesize, @handle, status)
    if raw.null?
      code = status.read_int
      klass = code == Leptris::XML::FFI::LEPTRIS_ERROR_PARSE ?
        Leptris::XML::ParseError : Leptris::XML::Error
      raise klass, "plan materialize failed (status=#{code})"
    end
    Leptris::XML::PlanValue.new(ResultHandle.new(raw),
                                owner: true, plans: @plans, plan: @plans[0])
  end
end
