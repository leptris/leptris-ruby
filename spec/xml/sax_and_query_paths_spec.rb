# frozen_string_literal: true

require "spec_helper"
RSpec.describe "round III: SAX adapter and query paths" do
  class EncodingProbeHandler < Leptris::XML::SAX::Document
    attr_reader :seen
    def initialize; @seen = {}; end
    def start_element(name, attrs); @seen[:name] = name; end
    def characters(text); @seen[:text] = text; end
    def comment(text); @seen[:comment] = text; end
    def processing_instruction(target, data); @seen[:pi] = [target, data]; end
    def cdata_block(text); @seen[:cdata] = text; end
    def error(msg, line, column); @seen[:error] = msg; end
  end

  it "delivers every SAX string kind as UTF-8" do
    handler = EncodingProbeHandler.new
    Leptris::XML::SAX::Parser.new(handler).parse(<<~XML)
      <!-- café -->
      <?target données?>
      <nom-élément attr="é">crème<![CDATA[données]]></nom-élément>
    XML
    expect(handler.seen[:name].encoding).to eq(Encoding::UTF_8)
    expect(handler.seen[:name]).to eq("nom-élément")
    expect(handler.seen[:text].encoding).to eq(Encoding::UTF_8)
    expect(handler.seen[:comment].encoding).to eq(Encoding::UTF_8)
    expect(handler.seen[:pi].map(&:encoding)).to all(eq(Encoding::UTF_8))
    expect(handler.seen[:cdata].encoding).to eq(Encoding::UTF_8)
  end

  it "reuses the handler struct across parses and honors a swap" do
    first = EncodingProbeHandler.new
    parser = Leptris::XML::SAX::Parser.new(first)
    parser.parse("<a/>")
    struct_before = parser.handler_struct
    parser.parse("<a/>")
    expect(parser.handler_struct).to equal(struct_before)

    second = EncodingProbeHandler.new
    parser.document = second
    parser.parse(%(<b attr="x"/>))
    expect(parser.handler_struct).not_to equal(struct_before)
    expect(second.seen[:name]).to eq("b")
    expect(first.seen[:name]).to eq("a")
  end

  it "rejects XPath variable bindings instead of ignoring them" do
    doc = Leptris::XML.parse("<r><a/></r>")
    expect { doc.root.xpath("//a", { "x" => "1" }, { "v" => "2" }) }
      .to raise_error(ArgumentError, /variable bindings/)
    # a single trailing hash is the namespace hash (Nokogiri semantics)
    expect { doc.root.xpath("//a", { "v" => "2" }) }.not_to raise_error
    expect { doc.root.xpath("//a", { "p" => "urn:p" }, {}) }.not_to raise_error
  end

  it "raises XPathError with engine detail on failed expressions" do
    doc = Leptris::XML.parse("<r/>")
    expect { doc.root.xpath("//a[") }
      .to raise_error(Leptris::XML::XPathError)
  end

  it "unions NodeSet#xpath without duplicate container churn" do
    doc = Leptris::XML.parse("<r><a><n>1</n></a><a><n>2</n></a><b><n>3</n></b></r>")
    as = doc.root.xpath("//a")
    result = as.xpath("./n")
    expect(result.map(&:content)).to eq(%w[1 2])
  end
end


RSpec.describe "round XVII: pull hot-loop reads" do
  it "reads events through the layout-derived offsets" do
    events = []
    Leptris::XML::Pull.parse(%(<?pi data?><!-- c --><r k="v">t<b/></r>)) do |e|
      events << e
    end
    types = events.map(&:type)
    expect(types).to eq(%i[pi comment start_element text start_element
                           end_element end_element end_document])
    pi = events.first
    expect(pi.name).to eq("pi")
    expect(pi.text).to eq("data")
    expect(pi.text.encoding).to eq(Encoding::UTF_8)
    start = events.find { |e| e.type == :start_element }
    expect(start.name).to eq("r")
    expect(start.attrs).to eq({ "k" => "v" })
    expect(start.attrs.keys.first.encoding).to eq(Encoding::UTF_8)
    text = events.find { |e| e.type == :text }
    expect(text.text).to eq("t")
  end

  it "answers nil attrs when the element has none" do
    events = []
    Leptris::XML::Pull.parse(%(<r><a/></r>)) { |e| events << e }
    inner = events.find { |e| e.name == "a" }
    expect(inner.attrs).to be_nil
  end
end

RSpec.describe "libleptris 1.9.4 surface" do
  it "records events in bulk with UTF-8 strings (SAX::Recorder)" do
    kinds = []
    attrs = nil
    Leptris::XML::SAX::Recorder.parse(
      %(<r k="v">caf\xc3\xa9<!--c--></r>)) do |kind, name, text, a, _l, _c|
      kinds << kind
      attrs = a if kind == :start_element
      expect([name, text].compact.map(&:encoding)).to all(eq(Encoding::UTF_8)) if text
    end
    expect(kinds).to eq(%i[start_document start_element characters comment
                           end_element end_document])
    expect(attrs).to eq({ "k" => "v" })
  end

  it "streams recorder events from an IO chunk by chunk" do
    require "stringio"
    kinds = []
    Leptris::XML::SAX::Recorder.parse(StringIO.new(%(<r><a/><b/></r>))) do |kind, *|
      kinds << kind
    end
    expect(kinds).to eq(%i[start_document start_element start_element
                           end_element start_element end_element
                           end_element end_document])
  end

  it "iterates full-document mode in post-order (v2 #586)" do
    order = []
    Leptris::XML::Iterparse.parse(
      %(<r><a><b/></a><c/></r>), mode: :full_document) do |el|
      order << el.name
    end
    expect(order).to eq(%w[b a c r])  # child before parent
  end

  it "resolves namespaces on the last yielded element" do
    scopes = []
    iter = Leptris::XML::Iterparse.parse(
      %(<r xmlns:p="urn:p"><p:a/><q:b xmlns:q="urn:q"/></r>))
    iter.run do |el|
      scopes << [el.name, iter.namespace_uri("p"), iter.namespace_uri("nope"),
                 iter.namespace_count, iter.error]
    end
    iter.free
    # element_name is the local name (DOM-consistent); the iterator's
    # snapshot is what resolves prefixes to URIs.
    expect(scopes).to eq(
      [["a", "urn:p", nil, 1, nil],
       ["b", "urn:p", nil, 2, nil]])
    expect(iter.error).to be_nil
  end

  it "reports the error channel for truncated input" do
    it = Leptris::XML::Iterparse.parse(%(<r><a>)) { |el| }
    expect(it.error).to be_a(String)
  end
end

RSpec.describe "round XIX: interest-proportional SAX" do
  it "leaves callbacks NULL when the handler does not override them" do
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |name, attrs = []| }
    end.new
    struct = Leptris::XML::SAX::Parser.new(handler).handler_struct
    expect(struct[:start_element]).not_to be_null
    expect(struct[:characters]).to be_null
    expect(struct[:end_element]).to be_null
    expect(struct[:error]).to be_null
  end

  it "delivers the overridden events with their payloads" do
    seen = []
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |name, attrs = []| seen << [:start, name, attrs] }
    end.new
    Leptris::XML::SAX::Parser.new(handler).parse(%(<r a="1"><a/>text</r>))
    expect(seen).to eq([[:start, "r", [["a", "1"]]], [:start, "a", []]])
  end

  it "parses with a handler that overrides nothing" do
    expect {
      Leptris::XML::SAX::Parser.new(Leptris::XML::SAX::Document.new)
        .parse(%(<r><a>x</a></r>))
    }.not_to raise_error
  end

  it "attaches what a duck-typed handler defines" do
    seen = []
    duck = Class.new do
      define_method(:start_element) { |name, attrs = []| seen << [:start, name] }
      define_method(:characters) { |text| seen << [:text, text] }
    end.new
    Leptris::XML::SAX::Parser.new(duck).parse(%(<r>x</r>))
    expect(seen).to eq([[:start, "r"], [:text, "x"]])
  end

  it "streams an IO through the pruned struct" do
    require "stringio"
    seen = []
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:end_element) { |name| seen << name }
    end.new
    Leptris::XML::SAX::Parser.new(handler).parse(StringIO.new(%(<r><a/></r>)))
    expect(seen).to eq(%w[a r])
  end

  it "drains only the requested kinds from the recorder" do
    seen = []
    Leptris::XML::SAX::Recorder.parse(
      %(<r a="1">t<!--c--></r>), kinds: [:start_element]) do |kind, name, _t, attrs|
      seen << [kind, name, attrs]
    end
    expect(seen).to eq([[:start_element, "r", { "a" => "1" }]])
  end

  it "filters per-chunk drains too" do
    require "stringio"
    seen = []
    Leptris::XML::SAX::Recorder.parse(
      StringIO.new(%(<r><a/>t</r>)), kinds: [:end_element]) do |kind, name|
      seen << [kind, name]
    end
    expect(seen).to eq([[:end_element, "a"], [:end_element, "r"]])
  end

  it "supports each_event filtering directly" do
    recorder = Leptris::XML::SAX::Recorder.open
    begin
      recorder.feed(%(<r><a/>t</r>), final: true)
      seen = []
      recorder.each_event(:characters) { |kind, _n, text| seen << [kind, text] }
      expect(seen).to eq([[:characters, "t"]])
    ensure
      recorder.free
    end
  end

  it "rejects unknown kinds" do
    expect {
      Leptris::XML::SAX::Recorder.parse(%(<r/>), kinds: [:nope]) { |*| }
    }.to raise_error(ArgumentError, /unknown event kinds/)
  end
end

RSpec.describe "round XXII: arity-declared SAX attrs interest" do
  it "delivers name-only to a one-argument start_element" do
    seen = []
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |name| seen << name }
    end.new
    expect {
      Leptris::XML::SAX::Parser.new(handler).parse(%(<r a="1"><b x="2"/></r>))
    }.not_to raise_error
    expect(seen).to eq(%w[r b])
  end

  it "still delivers attr pairs to optional-argument handlers" do
    seen = []
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |name, attrs = []| seen << [name, attrs] }
    end.new
    Leptris::XML::SAX::Parser.new(handler).parse(%(<r a="1"><b/></r>))
    expect(seen).to eq([["r", [["a", "1"]]], ["b", []]])
  end

  it "delivers name-only through the IO path too" do
    require "stringio"
    seen = []
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |name| seen << name }
    end.new
    Leptris::XML::SAX::Parser.new(handler).parse(StringIO.new(%(<r><a/></r>)))
    expect(seen).to eq(%w[r a])
  end
end

RSpec.describe "round XXVI: bulk SAX transport" do
  class CallRecorder < Leptris::XML::SAX::Document
    attr_reader :calls
    def initialize; @calls = []; end
    def start_document; @calls << :start_document; end
    def end_document; @calls << :end_document; end
    def start_element(name, attrs = []); @calls << [:start, name, attrs]; end
    def end_element(name); @calls << [:end, name]; end
    def characters(text); @calls << [:text, text]; end
    def comment(text); @calls << [:comment, text]; end
    def cdata_block(text); @calls << [:cdata, text]; end
    def processing_instruction(target, data); @calls << [:pi, target, data]; end
  end

  it "delivers identical calls through the auto-chosen bulk transport" do
    xml = %(<?pi p?><!--c--><r a="1"><a/>t<![CDATA[x]]></r>)
    via_parser = CallRecorder.new
    Leptris::XML::SAX::Parser.new(via_parser).parse(xml)
    via_dispatch = CallRecorder.new
    recorder = Leptris::XML::SAX::Recorder.open
    begin
      recorder.feed(xml, final: true)
      recorder.dispatch(via_dispatch, {
        start_document: true, end_document: true,
        start_element: true, end_element: true, characters: true,
        comment: true, cdata: true, pi: true,
      })
    ensure
      recorder.free
    end
    expect(via_parser.calls).to eq(via_dispatch.calls)
    expect(via_parser.calls.first(3)).to eq(
      [:start_document, [:pi, "pi", "p"], [:comment, "c"]])
  end

  it "keeps the one-argument start_element arity through the bulk path" do
    seen = []
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |name| seen << name }
      define_method(:characters) { |t| seen << t }
      define_method(:end_element) { |n| }
    end.new
    Leptris::XML::SAX::Parser.new(handler).parse(%(<r a="1"><a/>t</r>))
    expect(seen).to eq(%w[r a t])
  end
end

RSpec.describe "leptris-ruby#95: SAX attribute corruption" do
  let(:fixture) do
    '<iso-standard xmlns="http://riboseinc.com/isoxml">' \
      '<preface><foreword id="fwd">' \
      '<figure id="figureA-1" keep-with-next="true" keep-lines-together="true">' \
      '<figure id="note1">' \
      '<image src="rice_images/rice_image1.png" height="20" width="30" ' \
      'id="_8357ede4-6d44-4672-bac4-9a85e82ab7f0" mimetype="image/png" ' \
      'alt="alttext" title="titletxt"/></figure></figure></foreword></preface></iso-standard>'
  end

  def image_attrs(parser)
    got = nil
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |n, a = []| got = a if n == "image" }
    end.new
    parser.new(handler).parse(fixture)
    got
  end

  it "delivers every attribute intact through the DOM-backed default" do
    expect(image_attrs(Leptris::XML::SAX::Parser)).to eq(
      [["src", "rice_images/rice_image1.png"], ["height", "20"], ["width", "30"],
       ["id", "_8357ede4-6d44-4672-bac4-9a85e82ab7f0"],
       ["mimetype", "image/png"], ["alt", "alttext"], ["title", "titletxt"]])
  end

  it "delivers through IO and file paths identically" do
    require "stringio"
    got = nil
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |n, a = []| got = a if n == "image" }
    end.new
    Leptris::XML::SAX::Parser.new(handler).parse(StringIO.new(fixture))
    expect(got.size).to eq(7)
  end

  it "keeps the engine transports reachable via streaming: true" do
    got = nil
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |n, a = []| got = a if n == "image" }
    end.new
    Leptris::XML::SAX::Parser.new(handler, streaming: true).parse(fixture)
    # The ENGINE transports on this fixture corrupt the leading
    # pairs (that is #95) — this spec only pins that the opt-in
    # path still delivers an event stream, not that it is correct.
    expect(got.size).to be >= 3
    expect(git = got.last(3)).to eq(
      [["mimetype", "image/png"], ["alt", "alttext"], ["title", "titletxt"]])
  end
end

RSpec.describe "leptris-ruby#99: namespace declarations in SAX events" do
  let(:xml) do
    %q(<root xmlns:a="urn:a" xmlns="urn:d"><a:child a:attr="1">t</a:child></root>)
  end

  it "carries xmlns declarations as attribute pairs (engine contract)" do
    ev = []
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |n, a = []| ev << [n, a] }
    end.new
    Leptris::XML::SAX::Parser.new(handler).parse(xml)
    expect(ev).to eq(
      [["root", [["xmlns:a", "urn:a"], ["xmlns", "urn:d"]]],
       ["a:child", [["a:attr", "1"]]]])
    # interleaved at byte positions (upstream #635): a declaration
    # written between attributes reports between them
    mixed = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |n, a = []| ev.clear; ev << a }
    end.new
    Leptris::XML::SAX::Parser.new(mixed).parse(
      %q{<e xmlns:b="urn:b" id="1" xmlns="urn:d" x="2"/>})
    expect(ev[0]).to eq(
      [["xmlns:b", "urn:b"], ["id", "1"], ["xmlns", "urn:d"], ["x", "2"]])
  end

  it "keeps prefix-mapping events alongside the declaration pairs" do
    mappings = []
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_prefix_mapping) { |p, u| mappings << [p, u] }
    end.new
    Leptris::XML::SAX::Parser.new(handler).parse(xml)
    expect(mappings).to eq([["a", "urn:a"], ["", "urn:d"]])
  end

  it "matches the engine transport's pairs exactly, order included" do
    dom_ev = []
    d1 = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |n, a = []| dom_ev << [n, a] }
    end.new
    Leptris::XML::SAX::Parser.new(d1, streaming: false).parse(xml)
    eng_ev = []
    d2 = Class.new(Leptris::XML::SAX::Document) do
      define_method(:start_element) { |n, a = []| eng_ev << [n, a] }
    end.new
    Leptris::XML::SAX::Parser.new(d2).parse(xml)
    expect(dom_ev).to eq(eng_ev)
  end
end

RSpec.describe "pull batch staging corruption guard (leptris/leptris#646)" do
  it "delivers prefix events with the default namespace's empty prefix" do
    # short value: the staging corruption is real on engines <= 1.9.18
    # (fixed upstream in 1.9.21); this spec must stay clean on both
    v = "v" * 100
    xml = %(<r xmlns="urn:i"><a id="1"><b id="2"><image src="#{v}" a="1"/></b></a></r>)
    events = []
    Leptris::XML::Pull::Parser.parse(xml).each_batch(64) do |e|
      events << [e.type, e.name] if %i[start_prefix end_prefix start_element].include?(e.type)
    end
    expect(events.first).to eq(%i[start_prefix].zip([""]).first)
    expect(events).to include(%i[start_element].zip(%w[image]).first)
  end

  it "leaves healthy batches untouched" do
    seen = []
    Leptris::XML::Pull::Parser.parse("<r><a x=\"1\">t</a></r>")
      .each_batch(2) { |e| seen << [e.type, e.name] }
    expect(seen).to include([:start_element, "a"])
  end
end
