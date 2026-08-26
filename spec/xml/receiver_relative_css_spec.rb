# frozen_string_literal: true

require "spec_helper"
RSpec.describe "round V: receiver-relative css" do
  it "scopes element css to the element, not the document" do
    doc = Leptris::XML.parse(<<~XML)
      <r>
        <a><n>outer</n></a>
        <b><inner><n>deep</n></inner></b>
      </r>
    XML
    b = doc.root.element_children.find { |c| c.name == "b" }
    expect(b.css("n").map(&:content)).to eq(%w[deep])
    expect(b.css("inner > n").map(&:content)).to eq(%w[deep])
    expect(doc.css("n").length).to eq(2)
  end
end
