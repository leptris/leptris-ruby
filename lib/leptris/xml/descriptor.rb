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
class Leptris::XML::Descriptor
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
        ap[:type_tag] = row[:type_tag] || 0
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
        cp[:type_tag] = row[:type_tag] || 0
        cp[:child_plan_index] = row[:child_plan_index] || -1
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
end
