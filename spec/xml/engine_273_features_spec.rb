# frozen_string_literal: true

require "spec_helper"

# libleptris 1.9.272 Door A parse flags + 1.9.271 children snapshot:
# the two binding-facing features riding 1.9.273.
RSpec.describe "ParseOptions skip flags (engine 1.9.272)" do
  it "exposes the builders and predicates" do
    opts = Leptris::XML::ParseOptions.skip_dup_detection
    expect(opts).to be_skip_dup_detection
    expect(opts).not_to be_skip_source_positions

    opts = Leptris::XML::ParseOptions.skip_source_positions
    expect(opts).to be_skip_source_positions
    expect(opts).not_to be_skip_dup_detection
  end

  it "composes with |" do
    both = Leptris::XML::ParseOptions.skip_dup_detection |
           Leptris::XML::ParseOptions.skip_source_positions
    expect(both).to be_skip_dup_detection
    expect(both).to be_skip_source_positions
  end

  it "skipping source positions keeps lines resolving" do
    xml = "<r>\n  <a>x</a></r>"
    plain = Leptris::XML.parse(xml).root.element_children.first
    skipped = Leptris::XML.parse(
      xml, options: Leptris::XML::ParseOptions.skip_source_positions
    ).root.element_children.first
    expect(plain.source_position[:line]).to eq(2)
    expect(skipped.source_position[:line]).to eq(2)
  end

  it "skipping dup detection admits duplicates with first-wins reads" do
    xml = '<r a="first" a="second">t</r>'
    expect(Leptris::XML.parse(xml).root["a"]).to eq("first")
    expect(Leptris::XML.parse(
      xml, options: Leptris::XML::ParseOptions.skip_dup_detection
    ).root["a"]).to eq("first")
  end

  it "defaults stay byte-identical (zero flag word)" do
    xml = '<r a="1" b="2"><c>deep</c></r>'
    expect(Leptris::XML.parse(xml).root.to_xml)
      .to eq(Leptris::XML.parse(
               xml, options: Leptris::XML::ParseOptions.skip_dup_detection |
                    Leptris::XML::ParseOptions.skip_source_positions
             ).root.to_xml)
  end
end
