# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError # the pure-ruby fallback gem: the native faces stay absent
  nil
end

require "spec_helper"

# lutaml/moxml#548 / leptris-ruby#634: the factory-parameterized
# consumer-contract binding. The consumer registers its shape
# factories once per klass; the binding defines the contract's hot
# methods IN C - children serving the #530 memo'd list wrapped by
# the consumer's set factory, attribute serving the engine's
# decode-authoritative getter wrapped by the attribute factory.
# The context rides the primed @mx_context ivar.

# rubocop:disable Metrics/BlockLength -- the factories are the
# spec's fixtures; splitting them out obscures the contract shape
RSpec.describe "Native.bind_consumer_contract",
               if: defined?(Leptris::XML::NativeNode) do
  let(:hot_klass) { Class.new(Leptris::XML::NativeNode) }

  let(:set_factory) do
    Class.new do
      attr_reader :list, :context

      def initialize(list, context = nil)
        @list = list
        @context = context
      end
    end
  end

  let(:attr_factory) do
    Class.new do
      attr_reader :name, :value, :owner

      def initialize(name, value, owner = nil)
        @name = name
        @value = value
        @owner = owner
      end
    end
  end

  def bound_root
    doc = Leptris::XML::Document.parse(
      '<r a="1" p:x="2" xmlns:p="urn:p"><c>text</c><e/></r>'
    )
    Leptris::XML::Native.bind_consumer_contract(
      hot_klass, set_factory, attr_factory
    )
    # The klass-propagating children mints (#246) consult the
    # receiver class's child map - the consumer's install step.
    hot_klass.install_child_klasses(
      [hot_klass, hot_klass, nil, nil, nil]
    )
    [hot_klass.from(doc, doc.native_node), doc]
  end

  it "serves children through the set factory" do
    root, = bound_root
    kids = root.children
    expect(kids).to be_instance_of(set_factory)
    expect(kids.list.map(&:name)).to eq(%w[c e])
    expect(kids.list).to all(be_instance_of(hot_klass))
  end

  it "serves attributes through the attribute factory, decoded" do
    doc = Leptris::XML::Document.parse(
      '<r a="1" p:x="2" xmlns:p="urn:p"><e/></r>'
    )
    Leptris::XML::Native.bind_consumer_contract(
      hot_klass, set_factory, attr_factory
    )
    root = hot_klass.from(doc, doc.native_node)

    a = root.attribute("a")
    expect(a).to be_instance_of(attr_factory)
    expect(a.name).to eq("a")
    expect(a.value).to eq("1")

    px = root.attribute("p:x")
    expect(px.value).to eq("2")

    expect(root.attribute("missing")).to be_nil
  end

  it "propagates the bound klass through children mints" do
    root, = bound_root
    c = root.children.list[0]
    expect(c).to be_instance_of(hot_klass)
    expect(c.children).to be_instance_of(set_factory)
  end

  it "rejects non-subclasses" do
    expect do
      Leptris::XML::Native.bind_consumer_contract(
        Class.new(Object), set_factory, attr_factory
      )
    end.to raise_error(TypeError, /subclass/)
  end
end
# rubocop:enable Metrics/BlockLength
