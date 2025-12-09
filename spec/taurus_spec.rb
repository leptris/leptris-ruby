# frozen_string_literal: true

require "spec_helper"
require "taurus/document"

RSpec.describe Taurus do
  it "has a version number" do
    expect(Taurus::VERSION).not_to be nil
  end

  it "can parse XML" do
    xml = "<root>test</root>"
    doc = Taurus.parse(xml)

    expect(doc).to be_a(Taurus::Document)
    expect(doc.root.name).to eq("root")
    expect(doc.root.text).to eq("test")
  end
end
