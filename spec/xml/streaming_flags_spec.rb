# frozen_string_literal: true

require "spec_helper"
require "tempfile"

# Door A parse opt-outs on the streaming path (libleptris 1.9.283,
# #1459): LEPTRIS_PARSE_SKIP_DUP_DETECTION and
# LEPTRIS_PARSE_SKIP_SOURCE_POSITIONS reach iterparse, pull, the
# SAX recorder, and the callback SAX IO path. Duplicate attributes
# are admitted with the first value winning (DOM parity); error
# positions degrade to the last tracked state.
RSpec.describe "streaming Door A opt-outs (1.9.283)" do
  let(:dup_xml) do
    %(<log><entry id="1" id="2"><msg>a</msg></entry></log>)
  end
  let(:skip_dup) { Leptris::XML::ParseOptions.skip_dup_detection }

  it "iterparse admits duplicate attributes, first value wins" do
    flagless = []
    Leptris::XML::Iterparse.parse(dup_xml) { |e| flagless << e["id"] }
    expect(flagless).to eq([]) # parse failure yields nothing

    seen = []
    Leptris::XML::Iterparse.parse(dup_xml, options: skip_dup) do |e|
      seen << e["id"]
    end
    expect(seen).to eq(%w[1])
  end

  it "iterparse.parse_file carries the same opt-out" do
    file = Tempfile.new("dup")
    file.write(dup_xml)
    file.close
    begin
      seen = []
      Leptris::XML::Iterparse.parse_file(file.path, options: skip_dup) do |e|
        seen << e["id"]
      end
      expect(seen).to eq(%w[1])
    ensure
      file.unlink
    end
  end

  it "pull admits duplicate attributes, first value wins" do
    flagless = Leptris::XML::Pull::Parser.parse(dup_xml).each.to_a
    expect(flagless.map { |ev| ev[:type] }).to include(:error) # redefinition reported

    entries = Leptris::XML::Pull::Parser.parse(dup_xml, options: skip_dup).each.to_a
    entry = entries.find do |ev|
      ev[:type] == :start_element && ev[:name] == "entry"
    end
    expect(entry.attrs["id"]).to eq("1") # first value, DOM parity
  end

  it "the SAX recorder accepts the position opt-out" do
    recorder = Leptris::XML::SAX::Recorder.open(
      options: Leptris::XML::ParseOptions.skip_source_positions
    )
    begin
      recorder.feed(dup_xml, final: true)
      seen = []
      recorder.each_event(:start_element) { |kind, name, *| seen << [kind, name] }
      expect(seen).to include([:start_element, "entry"])
    ensure
      recorder.free
    end
  end

  it "default (no options) keeps the flagless C twins" do
    names = []
    Leptris::XML::Iterparse.parse("<root><a/></root>") do |el|
      names << el.name
    end
    expect(names).to eq(%w[a])
  end

  it "rejects non-ParseOptions option objects" do
    expect do
      Leptris::XML::Iterparse.parse("<r/>", options: 0x4) { |_e| }
    end.to raise_error(ArgumentError, /ParseOptions/)
  end
end
