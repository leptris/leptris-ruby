# frozen_string_literal: true

require "taurus/xml"
require "stringio"

RSpec.describe Taurus::XML::SAX::Parser do
  let(:xml) do
    <<~XML
      <?xml version="1.0"?>
      <library xmlns="http://default.example" xmlns:foo="http://foo.example">
        <book id="1"><title lang="en">Ruby</title></book>
        <book id="2"><!-- a note --><title>XML</title></book>
      </library>
    XML
  end

  # Test handler that captures every event into an array for assertion.
  class RecordingHandler < Taurus::XML::SAX::Document
    attr_reader :events

    def initialize
      @events = []
    end

    def start_document; @events << [:start_document]; end
    def end_document;   @events << [:end_document]; end

    def start_element(name, attrs = [])
      @events << [:start_element, name, attrs]
    end
    def end_element(name)
      @events << [:end_element, name]
    end
    def characters(string)
      @events << [:characters, string] unless string.strip.empty?
    end
    def comment(string)
      @events << [:comment, string]
    end
    def cdata_block(string)
      @events << [:cdata, string]
    end
    def processing_instruction(name, content)
      @events << [:pi, name, content]
    end
    def start_prefix_mapping(prefix, uri)
      @events << [:start_prefix, prefix, uri]
    end
    def end_prefix_mapping(prefix)
      @events << [:end_prefix, prefix]
    end
    def error(message, line = 0, column = 0)
      @events << [:error, message, line, column]
    end
  end

  describe "#parse_memory" do
    it "delivers start_element / end_element events with attrs as [name, value] pairs" do
      h = RecordingHandler.new
      described_class.new(h).parse_memory(%q{<book id="1" lang="en"/>})
      expect(h.events).to include([:start_element, "book", [["id", "1"], ["lang", "en"]]])
      expect(h.events).to include([:end_element, "book"])
    end

    it "delivers characters events" do
      h = RecordingHandler.new
      described_class.new(h).parse_memory("<x>hello world</x>")
      chars = h.events.select { |e| e[0] == :characters }.map { |e| e[1] }
      expect(chars.join).to eq("hello world")
    end

    it "delivers comment events" do
      h = RecordingHandler.new
      described_class.new(h).parse_memory("<x><!-- a note --></x>")
      expect(h.events).to include([:comment, " a note "])
    end

    it "delivers cdata events" do
      h = RecordingHandler.new
      described_class.new(h).parse_memory("<x><![CDATA[<raw>]]></x>")
      expect(h.events).to include([:cdata, "<raw>"])
    end

    it "delivers processing_instruction events" do
      h = RecordingHandler.new
      described_class.new(h).parse_memory(%q{<?xml-stylesheet type="text/xsl"?><x/>})
      pis = h.events.select { |e| e[0] == :pi }
      expect(pis.length).to eq(1)
      expect(pis.first[1]).to eq("xml-stylesheet")
      expect(pis.first[2]).to eq('type="text/xsl"')
    end

    it "delivers start_prefix_mapping events for namespace declarations" do
      h = RecordingHandler.new
      described_class.new(h).parse_memory(%q{<x xmlns:foo="http://foo.example"/>})
      prefix_events = h.events.select { |e| e[0] == :start_prefix }
      expect(prefix_events).to include([:start_prefix, "foo", "http://foo.example"])
    end

    it "delivers start_document and end_document" do
      h = RecordingHandler.new
      described_class.new(h).parse_memory("<x/>")
      expect(h.events.first).to eq([:start_document])
      expect(h.events.last).to eq([:end_document])
    end

    it "walks the full event sequence in document order" do
      h = RecordingHandler.new
      described_class.new(h).parse_memory(%q{<lib><book id="1">text</book></lib>})
      tags = h.events.select { |e| %i[start_element end_element].include?(e[0]) }
                     .map { |e| [e[0], e[1]] }
      expect(tags).to eq([
        [:start_element, "lib"],
        [:start_element, "book"],
        [:end_element, "book"],
        [:end_element, "lib"]
      ])
    end
  end

  describe "#parse_io (streaming via feed)" do
    it "parses the same events as parse_memory" do
      h1 = RecordingHandler.new
      h2 = RecordingHandler.new
      described_class.new(h1).parse_memory(xml)
      described_class.new(h2).parse_io(StringIO.new(xml))

      # Streaming may split characters events across chunk boundaries.
      # Compare element/structure events only.
      structure = ->(events) do
        events.select { |e| %i[start_element end_element comment cdata pi start_prefix].include?(e[0]) }
      end
      expect(structure.call(h1.events)).to eq(structure.call(h2.events))
    end

    it "handles chunks larger than the buffer" do
      big = "<r>" + ("x" * 10_000) + "</r>"
      h = RecordingHandler.new
      described_class.new(h).parse_io(StringIO.new(big))
      tags = h.events.select { |e| %i[start_element end_element].include?(e[0]) }
                     .map { |e| [e[0], e[1]] }
      expect(tags).to eq([[:start_element, "r"], [:end_element, "r"]])
    end
  end

  describe "#parse (auto-dispatch)" do
    it "uses parse_memory for strings" do
      h = RecordingHandler.new
      described_class.new(h).parse("<x/>")
      expect(h.events).to include([:start_element, "x", []])
    end

    it "uses parse_io for IO objects" do
      h = RecordingHandler.new
      described_class.new(h).parse(StringIO.new("<x/>"))
      expect(h.events).to include([:start_element, "x", []])
    end

    it "raises ArgumentError for unsupported types" do
      expect { described_class.new.parse(42) }
        .to raise_error(ArgumentError, /String or IO/)
    end
  end

  describe "#parse_file" do
    it "parses from a file path" do
      require "tmpdir"
      path = File.join(Dir.mktmpdir, "test.xml")
      File.write(path, "<x><y/></x>")
      h = RecordingHandler.new
      described_class.new(h).parse_file(path)
      expect(h.events).to include([:start_element, "x", []])
      expect(h.events).to include([:start_element, "y", []])
    end
  end

  describe "default Document handler" do
    it "does not raise when no handler is supplied" do
      expect { described_class.new.parse("<x/>") }.not_to raise_error
    end
  end
end
