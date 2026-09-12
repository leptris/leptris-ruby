# frozen_string_literal: true

RSpec.describe "Leptris::XML.diff (libleptris 1.9.144 family)" do
  it "reports text, attribute, and structural ops with paths" do
    a = Leptris::XML::Document.parse("<r><i>one</i><j x='1'/></r>")
    b = Leptris::XML::Document.parse("<r><i>ONE</i><j x='2'/><k/></r>")
    ops = Leptris::XML.diff(a, b).ops
    by_path = ops.each_with_object({}) { |op, h| h[op[:path]] = op }
    expect(by_path["/r/i"]).to include(type: :update_text, before: "one", after: "ONE")
    expect(by_path["/r/j"]).to include(type: :update_attr, before: "1", after: "2")
    expect(by_path["/r/k[1]"]).to include(type: :insert)
  end

  it "prunes equal subtrees entirely" do
    a = Leptris::XML::Document.parse("<r><same>identical</same><i>1</i></r>")
    b = Leptris::XML::Document.parse("<r><same>identical</same><i>2</i></r>")
    ops = Leptris::XML.diff(a, b).ops
    expect(ops.size).to eq(1)
    expect(ops.first[:path]).to eq("/r/i")
  end

  it "serializes the op list" do
    a = Leptris::XML::Document.parse("<r><i>1</i></r>")
    b = Leptris::XML::Document.parse("<r><i>2</i></r>")
    expect(Leptris::XML.diff(a, b).to_s).to include("/r/i", "1", "2")
  end
end
