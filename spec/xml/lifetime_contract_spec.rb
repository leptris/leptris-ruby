# frozen_string_literal: true

require "spec_helper"
RSpec.describe "round IV: borrowed-handle lifetime" do
  let(:doc) { Leptris::XML.parse(%(<r a="1"><c>x<!--k--></c></r>)) }
  let(:root) { doc.root }
  let(:child) { root.element_children.first }
  let(:text) { child.children.find(&:text?) }

  before { doc.free }

  it "raises UseAfterFreeError on stale element reads" do
    expect { root.name }.to raise_error(Leptris::XML::UseAfterFreeError)
    expect { root["a"] }.to raise_error(Leptris::XML::UseAfterFreeError)
    expect { root.children }.to raise_error(Leptris::XML::UseAfterFreeError)
    expect { root.next_sibling }.to raise_error(Leptris::XML::UseAfterFreeError)
    expect { root.namespaces }.to raise_error(Leptris::XML::UseAfterFreeError)
  end

  it "raises UseAfterFreeError on stale non-element reads" do
    expect { text.content }.to raise_error(Leptris::XML::UseAfterFreeError)
  end

  it "raises UseAfterFreeError on stale mutations" do
    expect { root["a"] = "2" }.to raise_error(Leptris::XML::UseAfterFreeError)
    expect { root.name = "z" }.to raise_error(Leptris::XML::UseAfterFreeError)
    expect { text.content = "x" }.to raise_error(Leptris::XML::UseAfterFreeError)
  end

  it "answers Document#freed? truthfully" do
    live = Leptris::XML.parse("<r/>")
    expect(live.freed?).to be false
    expect(doc.freed?).to be true
    live.free
    expect(live.freed?).to be true
  end
end

