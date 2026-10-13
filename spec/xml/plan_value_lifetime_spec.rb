# frozen_string_literal: true

require "spec_helper"

# #1673: child PlanValue views borrow their pointers from the
# root's result arena. The root's whole-result handle frees the
# arena at GC — a Ruby-3.3-timed collection could free it while
# borrowed views were still live (the ride's linux/3.3 segfault).
# Children now retain the lifetime root transitively.
RSpec.describe "PlanValue lifetime retention (#1673)" do
  let(:plan) do
    Leptris::XML::Descriptor.build(
      name: "fonts", ns: { exact: "urn:w" }, ns_prefix: "w",
      children: [
        { name: "font", kind: :nested, ns: { exact: "urn:w" },
          ns_prefix: "w", plan: {
            name: "font", ns: { exact: "urn:w" },
            children: [
              { name: "sz", kind: :scalar,
                ns: { exact: "urn:w" }, ns_prefix: "w" }
            ]
          } }
      ]
    )
  end
  let(:doc) do
    Leptris::XML::Document.parse(
      %(<w:fonts xmlns:w="urn:w">) +
      %(<w:font><w:sz>12</w:sz></w:font>) +
      %(<w:font><w:sz>14</w:sz></w:font></w:fonts>)
    )
  end

  it "children stay readable after the root becomes unreachable" do
    kids = nil
    plan.walk(doc.root).then do |root|
      kids = root.children_snapshot[2]
    end
    GC.start
    expect(kids.map { |k| k.children_snapshot[2].first.string_value })
      .to eq(%w[12 14])
  end

  it "the serialized form survives the root going unreachable" do
    kids = nil
    plan.walk(doc.root).then do |root|
      kids = root.children_snapshot[2]
    end
    GC.start
    expect(plan.serialize(kids.first)).to include("<w:sz>12</w:sz>")
  end

  it "serialize_ext through a borrowed child survives GC" do
    kid = nil
    plan.walk(doc.root).then do |root|
      kid = root.children_snapshot[2].first
    end
    GC.start
    expect(plan.serialize(kid, indent: 2)).to include("<w:sz>12</w:sz>")
  end
end
