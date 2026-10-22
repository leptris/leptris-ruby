# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# leptris-ruby#530: the walk-row read memos. name_read and
# children_read — the two reads a tree walk pays per node — are
# memoized on the native wrapper, stamped with the document's
# mutation version (the content-memo discipline, ADR 0003). On
# registered-consumer documents (#340 doc-klass map) the FIRST cold
# children_read primes the whole subtree's element memos in ONE
# crossing (the #527 walk machinery); walked nodes then serve
# struct hits. Any mutation — binding or native face — bumps the
# version and retires the memos subtree-wide.
RSpec.describe "NativeNode walk-read memos (#530)",
               if: defined?(Leptris::XML::NativeNode) do
  let(:doc) do
    Leptris::XML::Document.parse(
      %(<r><a>one<b/>two</a><c/><d x="1"><e/></d></r>))
  end

  let(:root) { doc.native_node }

  def deep
    root.children_read[2].children_read[0] # d/e
  end

  describe "children_read memo" do
    it "serves repeat reads the same list with wrapper identity" do
      first = root.children_read
      again = root.children_read
      expect(again).to equal(first)
      expect(first.map(&:name)).to eq(%w[a c d])
      # identity: the wrappers are the native-cache entries, stable
      # across every read path
      expect(first[0]).to equal(root.children_read[0])
    end

    it "retires on a native-face mutation" do
      expect(root.children_read.map(&:name)).to eq(%w[a c d])
      root.append_child(root.create_child("z"))
      expect(root.children_read.map(&:name)).to eq(%w[a c d z])
    end

    it "retires on a binding-face mutation" do
      expect(root.children_read.size).to eq(3)
      doc.root.add_child(doc.create_element("z"))
      expect(doc.native_node.children_read.map(&:name))
        .to eq(%w[a c d z])
    end
  end

  describe "name_read memo" do
    it "serves repeat reads the identical interned name" do
      a = root.children_read[0]
      expect(a.name).to eq("a")
      expect(a.name).to equal(a.name)
    end

    it "retires on a rename" do
      a = root.children_read[0]
      expect(a.name).to eq("a")
      doc.root.children.first.name = "renamed"
      expect(a.name).to eq("renamed")
    end

    it "answers the same nameless-kind read, memoized" do
      text = root.children_read[0].children_read[0]
      first = text.name
      expect(first).to eq("")
      expect(text.name).to equal(first)
    end
  end

  describe "registered-consumer subtree prime" do
    it "one cold read serves the whole subtree with identity" do
      el = Class.new(Leptris::XML::NativeNode)
      tx = Class.new(Leptris::XML::NativeNode)
      doc.register_wrapper_klasses([el, tx, nil, nil, nil])

      root.children_read # the prime crossing
      # every element under the asked node now serves its list from
      # the prime — same wrappers the walk mints, same names
      expect(deep.name).to eq("e")
      expect(deep.children_read).to be_empty
      a = root.children_read[0]
      expect(a).to be_instance_of(el)
      expect(a.children_read[0]).to be_instance_of(tx) # "one"
      expect(a.children_read[1]).to be_instance_of(el) # <b/>
      expect(a.children_read.map(&:name)).to eq(["", "b", ""])
      # re-reads answer the same list
      expect(a.children_read).to equal(a.children_read)
    end

    it "prime results equal the engine truth walk_columnar sees" do
      el = Class.new(Leptris::XML::NativeNode)
      doc.register_wrapper_klasses([el, nil, nil, nil, nil])
      root.children_read
      names, handles, depths = Leptris::XML::Native.walk_columnar(root)

      # rebuild the parent chain from depths (the moxml #435 shape)
      stack = []
      expected = {}
      handles.each_with_index do |handle, i|
        depth = depths[i]
        stack[depth] = handle
        expected[handle] ||= []
        expected[stack[depth - 1]] << handle if depth.positive?
      end
      expected.each do |parent, children|
        expect(parent.children_read).to eq(children)
        expect(parent.children_read.map(&:name))
          .to eq(children.map(&:name))
      end
      # and the names answer what the columnar walk saw (the walk's
      # names are nil for nameless kinds; name_read answers "")
      handles.each_with_index do |handle, i|
        if names[i]
          expect(handle.name).to eq(names[i])
        else
          expect(handle.name).to eq("")
        end
      end
    end

    it "a mutation after the prime is visible on deep nodes" do
      doc.register_wrapper_klasses(
        [Leptris::XML::NativeNode, nil, nil, nil, nil])
      root.children_read # prime
      d = root.children_read[2]
      d.append_child(d.create_child("late"))
      expect(d.children_read.map(&:name)).to eq(%w[e late])
      # the root memo retired too: fresh read sees the same doc
      expect(root.children_read[2].children_read.map(&:name))
        .to eq(%w[e late])
    end
  end
end
