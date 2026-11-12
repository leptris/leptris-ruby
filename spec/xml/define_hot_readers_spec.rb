# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# TODO.perf/39(a) (leptris-ruby#622 ask 1): hot readers parameterized
# by subclass. Consumer wrapper classes SUBCLASS NativeNode and shadow
# its C readers with included Ruby modules — every shadowed read pays
# an UnboundMethod#bind_call frame. define_hot_readers installs the
# SAME C bodies directly on the subclass, so lookup answers in C with
# no shadow in the chain. Which classes go hot is the consumer's
# per-document klass-map decision (#340) — entity-bearing documents
# can keep contract classes while clean documents go hot.
RSpec.describe "Native.define_hot_readers",
               if: defined?(Leptris::XML::NativeNode) do
  let(:hot_klass) { Class.new(Leptris::XML::NativeNode) }

  it "defines the C readers directly on the subclass, beating shadows" do
    doc = Leptris::XML::Document.parse(%q{<r a="1" p:x="2" xmlns:p="urn:p"><c>text</c>tail</r>})

    # A Ruby module shadow exactly like a consumer's contract module:
    # before the hot install it wins lookup over the inherited C method.
    shadow = Module.new do
      define_method(:name) { "SHADOWED" }
    end
    hot_klass.include(shadow)

    root = hot_klass.from(doc, doc.native_node)
    expect(root.name).to eq("SHADOWED")

    Leptris::XML::Native.define_hot_readers(hot_klass)

    # Lookup now answers the C body — interning + the walk-memo —
    # not the shadow.
    expect(root.name).to eq("r")
    expect(root.name).to be_frozen
    expect(root.attribute("a")).to eq("1")
    expect(root.attribute("p:x")).to eq("2")
    expect(root.content).to eq("texttail")

    # A second mint from the cache keeps the hot surface.
    expect(hot_klass.from(doc, doc.native_node).name).to eq("r")
  end

  it "rejects classes that do not subclass NativeNode" do
    expect { Leptris::XML::Native.define_hot_readers(Class.new(Object)) }
      .to raise_error(TypeError, /subclass/)

    expect { Leptris::XML::Native.define_hot_readers("not a class") }
      .to raise_error(TypeError, /expected a class/)
  end
end
