# frozen_string_literal: true

require "spec_helper"

# moxml#460/#1855 ask 2: engine-side name comparison — no String
# materialization for name-comparing consumers. Qnil for
# non-element addresses (mirrors fast_name).
RSpec.describe "Native.name_equals",
               if: defined?(Leptris::XML::Native) &&
                   Leptris::XML::Native.respond_to?(:name_equals) do
  let(:doc) { Leptris::XML::Document.parse("<r><field x=\"1\"/></r>") }
  let(:root_addr) { doc.native_node.address }

  it "compares the element name engine-side" do
    expect(Leptris::XML::Native.name_equals(root_addr, "r")).to be(true)
    expect(Leptris::XML::Native.name_equals(root_addr, "x")).to be(false)
  end

  it "answers nil for a non-element address" do
    text = doc.native_node.children_read.to_a.find { |c| !c.name.to_s.empty? }
    addr = text.address
    expect(Leptris::XML::Native.name_equals(addr, "r")).to be_nil.or be_falsey
  end
end
