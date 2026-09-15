# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
  RSpec.describe "Leptris::XML::NativeNode" do
    it "raises a clear error when the bundle is absent" do
      pending "native bundle not vendored in this install"
      raise
    end
  end
  return
end

RSpec.describe "Leptris::XML::NativeNode (opt-in native read layer, #185)" do
  let(:doc) do
    Leptris::XML::Document.parse(
      %q{<r><a x="1">t1</a><a x="2">t2</a><!--c--><b/></r>})
  end
  let(:root) { doc.native_node }

  it "reads children with types and element_children filtered" do
    expect(root.children.map(&:node_type))
      .to eq(%i[element element comment element])
    expect(root.element_children.map(&:name)).to eq(%w[a a b])
  end

  it "reads names, attributes, and content" do
    first = root.element_children.first
    expect(first.name).to eq("a")
    expect(first["x"]).to eq("1")
    expect(first.content).to eq("t1")
    expect(first.attribute("missing")).to be_nil
  end

  it "walks siblings and parents with identity" do
    first, second, = root.element_children.to_a
    expect(first.next_sibling).to eq(second)
    expect(second.parent).to equal(root)
    expect(root.parent).to be_nil
  end

  it "shares identity with the binding through the wrapper cache" do
    native_first = root.element_children.first
    binding_first = doc.root.element_children.first
    expect(native_first.name).to eq(binding_first.name)
    # repeated native reads return the same object
    expect(root.element_children.first)
      .to equal(native_first)
  end

  it "materializes a typed walk far faster than the binding path (gate)" do
    items = Leptris::XML::Document.parse(
      %(<r>) + (1..150).map { |i|
        %(<rec id="#{i}"><name>rec #{i}</name><val>#{i}</val></rec>)
      }.join + %(</r>))
    native_root = items.native_node
    names = native_root.element_children.map { |r| r["id"] }
    expect(names).to eq((1..150).map(&:to_s))
    expect(native_root.element_children.first.content).to include("rec 1")
  end
end

RSpec.describe "Native builder factories (#149)" do
  it "creates elements and text without the wrap_fresh path" do
    doc = Leptris::XML::Document.create
    root = doc.native_create_element("r")
    doc.native_root = root
    child = doc.native_create_element("field")
    text = doc.native_create_text("value")
    child.add_child(text)
    root.add_child(child)
    expect(root.element_children.map(&:name)).to eq(%w[field])
    expect(root.element_children.first.content).to eq("value")
  end

  it "create_child fuses create+append" do
    doc = Leptris::XML::Document.create
    root = doc.native_create_element("r")
    doc.native_root = root
    a = root.create_child("a")
    b = root.create_child("b")
    expect(root.element_children.map(&:name)).to eq(%w[a b])
    expect(a.parent.equal?(root)).to be(true)
  end

  it "keeps binding Document#root working after native_root=" do
    doc = Leptris::XML::Document.create
    root = doc.native_create_element("r")
    doc.native_root = root
    expect(doc.root).to be_a(Leptris::XML::Element)
    expect(doc.root.name).to eq("r")
    expect(doc.native_node.name).to eq("r")
  end
end

RSpec.describe "NativeNode surface completion (TODO.perf/05)" do
  it "reads the attribute hash in one C walk (string values)" do
    doc = Leptris::XML::Document.parse(%q{<rec id="7" sku="S7">x</rec>})
    rec = doc.native_node
    expect(rec.attributes).to eq("id" => "7", "sku" => "S7")
    expect(rec.attributes.keys).to eq(%w[id sku])
  end

  it "reads line and byte_offset with binding parity" do
    doc = Leptris::XML::Document.parse(%q{<r><rec id="7">x</rec></r>})
    native_rec = doc.native_node.element_children.first
    binding_rec = doc.root.element_children.first
    expect(native_rec.line).to eq(binding_rec.line)
    expect(native_rec.byte_offset).to eq(binding_rec.byte_offset)
    expect(native_rec.byte_offset).to be > 0
  end
end

RSpec.describe "bulk paths never truncate (#202)" do
  it "returns every child past the 512 batch floor" do
    [511, 512, 513, 600, 1000].each do |n|
      doc = Leptris::XML::Document.parse(
        "<r>" + (1..n).map { |i| i.even? ? "<c/>" : "t" }.join + "</r>")
      expect(doc.native_node.children.size).to eq(n)
      expect(doc.root.children.size).to eq(n)
      expect(doc.native_node.element_children.size)
        .to eq((1..n).count(&:even?))
    end
  end

  it "materializes xpath results past the floor" do
    doc = Leptris::XML::Document.parse("<r>" + ("<e/>" * 800) + "</r>")
    expect(doc.xpath("//e").size).to eq(800)
  end
end

RSpec.describe "NativeNode#document (moxml #213)" do
  it "returns the owning binding Document for self and descendants" do
    doc = Leptris::XML::Document.parse(%q{<r><a/></r>})
    root = doc.native_node
    expect(root.document).to equal(doc)
    expect(root.element_children.first.document).to equal(doc)
  end
end

RSpec.describe "C-bound mutation and read floors (TODO.perf/07-10, #204)" do
  it "add_child through the C face keeps binding memos coherent" do
    doc = Leptris::XML::Document.parse(%q{<r/>})
    before = doc.root.children.to_a
    doc.root.add_child(doc.create_element("made"))
    after = doc.root.children.to_a
    expect(after.map(&:name)).to eq(%w[made])
    expect(after).not_to equal(before)
  end

  it "add_child still lifts namespaces for namespaced children (Qnil fallback)" do
    doc = Leptris::XML::Document.parse(%q{<r/>})
    src = Leptris::XML::Document.parse(
      %q{<a:o xmlns:a="urn:a"><a:i/></a:o>})
    inner = src.root.element_children.first
    doc.root.add_child(inner)
    expect(doc.root.to_xml)
      .to eq(%q{<r><a:i xmlns:a="urn:a"/></r>})
  end

  it "add_child appends text children without materializing namespaces" do
    doc = Leptris::XML::Document.parse(%q{<r/>})
    doc.root.add_child(doc.create_text_node("t"))
    expect(doc.root.content).to eq("t")
  end

  it "add_child raises ReadOnlyError and UseAfterFreeError through the C face" do
    doc = Leptris::XML::Document.parse(%q{<r/>})
    doc.readonly!
    expect { doc.root.add_child(doc.create_element("x")) }
      .to raise_error(Leptris::XML::ReadOnlyError)

    freed = Leptris::XML::Document.parse(%q{<r/>})
    handle = freed.root
    freed.free
    expect { handle.add_child(Leptris::XML::Document.create.create_element("x")) }
      .to raise_error(Leptris::XML::UseAfterFreeError)
  end

  it "[]= goes through the C face and drops attribute memos on both surfaces" do
    doc = Leptris::XML::Document.parse(%q{<r a="1"/>})
    native = doc.native_node
    expect(native["a"]).to eq("1")
    doc.root["a"] = "2"
    doc.root["b"] = "3"
    expect(native["a"]).to eq("2")
    expect(native["b"]).to eq("3")
    expect(doc.root["a"]).to eq("2")
  end

  it "[]= raises ReadOnlyError through the C face" do
    doc = Leptris::XML::Document.parse(%q{<r/>})
    doc.readonly!
    expect { doc.root["a"] = "1" }
      .to raise_error(Leptris::XML::ReadOnlyError)
  end

  it "NativeNode attribute reads memoize and invalidate on mutation" do
    doc = Leptris::XML::Document.parse(%q{<r sku="S7"/>})
    node = doc.native_node
    first = node["sku"]
    expect(node["sku"]).to equal(first)
    doc.root["sku"] = "CHANGED"
    expect(node["sku"]).to eq("CHANGED")
  end

  it "NativeNode content memoizes and invalidates on native mutation" do
    doc = Leptris::XML::Document.parse(%q{<r><e>old</e></r>})
    root = doc.native_node
    expect(root.content).to eq("old")
    root.append_child(Leptris::XML::NativeNode.create_text(doc, "+new"))
    expect(root.content).to eq("old+new")
    expect(doc.root.content).to eq("old+new")
  end

  it "Element.skip_adoption_lift? answers provable no-ops exactly" do
    plain = Leptris::XML::Document.parse(%q{<r><e/></r>})
    expect(Leptris::XML::Element.skip_adoption_lift?(
             plain.root.element_children.first)).to be(true)

    pfx = Leptris::XML::Document.parse(
      %q{<a:o xmlns:a="urn:a"><a:i/></a:o>})
    expect(Leptris::XML::Element.skip_adoption_lift?(
             pfx.root.element_children.first)).to be(false)

    default_ns = Leptris::XML::Document.parse(
      %q{<o xmlns="urn:d"><i/></o>})
    expect(Leptris::XML::Element.skip_adoption_lift?(
             default_ns.root.element_children.first)).to be(false)

    text = Leptris::XML::Document.parse(%q{<r>t</r>})
    expect(Leptris::XML::Element.skip_adoption_lift?(
             text.root.children.first)).to be(true)
  end
end

RSpec.describe "structural memos (TODO.perf/13)" do
  it "answers parent correctly after a same-document move (FFI-seeded wrappers too)" do
    doc = Leptris::XML::Document.parse(%q{<r><a><child/></a><b/></r>})
    a, b = doc.root.element_children
    child = a.element_children.first
    expect(child.parent.name).to eq("a")
    b.add_child(child)
    expect(child.parent.name).to eq("b")
    expect(child.parent).to equal(b)
  end

  it "answers parent correctly after a cross-document move" do
    doc = Leptris::XML::Document.parse(%q{<r><slot/></r>})
    src = Leptris::XML::Document.parse(%q{<s><x><m/></x></s>})
    moved = src.root.element_children.first
    doc.root.add_child(moved)
    expect(moved.parent.name).to eq("r")
    expect(src.root.element_children.size).to eq(0)
  end

  it "answers siblings correctly after unlink and insert" do
    doc = Leptris::XML::Document.parse(%q{<r><a/><b/><c/></r>})
    a, b, c = doc.root.element_children
    expect(a.next_sibling).to equal(b)
    expect(b.previous_sibling).to equal(a)
    b.unlink
    expect(a.next_sibling).to equal(c)
    expect(c.previous_sibling).to equal(a)
    a.add_next_sibling(doc.create_element("x"))
    expect(a.next_sibling.name).to eq("x")
  end

  it "memoizes Document#root with identity" do
    doc = Leptris::XML::Document.parse(%q{<r><a/></r>})
    expect(doc.root).to equal(doc.root)
    doc.root = doc.create_element("q")
    expect(doc.root.name).to eq("q")
    expect(doc.root).to equal(doc.root)
  end
end

RSpec.describe "C-bound insert family (TODO.perf/14)" do
  it "prepends and inserts around the anchor" do
    doc = Leptris::XML::Document.parse(%q{<r><a/><b/></r>})
    a, b = doc.root.element_children
    b.prepend_child(doc.create_element("first"))
    a.add_next_sibling(doc.create_element("after"))
    a.add_previous_sibling(doc.create_element("before"))
    expect(doc.root.element_children.map(&:name))
      .to eq(%w[before a after b])
    expect(b.element_children.map(&:name)).to eq(%w[first])
  end

  it "falls back to the lift path for namespaced children" do
    doc = Leptris::XML::Document.parse(%q{<r><a/></r>})
    src = Leptris::XML::Document.parse(
      %q{<a:o xmlns:a="urn:a"><a:i/></a:o>})
    doc.root.element_children.first.prepend_child(
      src.root.element_children.first)
    expect(doc.root.element_children.first.children.first.to_xml)
      .to eq(%q{<a:i xmlns:a="urn:a"/>})
  end

  it "raises ReadOnlyError through the insert faces" do
    doc = Leptris::XML::Document.parse(%q{<r/>})
    doc.readonly!
    expect { doc.root.prepend_child(doc.create_element("x")) }
      .to raise_error(Leptris::XML::ReadOnlyError)
  end
end

RSpec.describe "compiled-expression cache (TODO.perf/15)" do
  it "returns identical results through the cache" do
    doc = Leptris::XML::Document.parse(
      %q{<r><item id="7"><name>x</name></item></r>})
    expect(doc.xpath("//item[@id='7']").map(&:name)).to eq(%w[item])
    expect(doc.xpath("//item[@id='7']").map(&:name)).to eq(%w[item])
    expect(doc.at_xpath("//name").content).to eq("x")
    expect(doc.xpath("count(//item)")).to eq(1.0)
    expect(doc.xpath("string(//name)")).to eq("x")
    expect(doc.at_xpath("//missing")).to be_nil
  end

  it "does not cache failed compiles" do
    cache = Leptris::XML::Searchable.instance_variable_get(:@compiled_expressions)
    before = cache ? cache.size : 0
    doc = Leptris::XML::Document.parse(%q{<r/>})
    expect { doc.xpath("///[bad(") }
      .to raise_error(Leptris::XML::XPathError)
    after = Leptris::XML::Searchable.instance_variable_get(:@compiled_expressions)
    expect(after.size).to eq(before)
  end

  it "keeps namespace-bound and version-pinned paths on their entries" do
    doc = Leptris::XML::Document.parse(
      %q{<r><p:x xmlns:p="urn:p">y</p:x></r>})
    expect(doc.root.xpath(".//p:x", "p" => "urn:p").first.content)
      .to eq("y")
    expect { doc.xpath("//p:x", version: "1.0") }.not_to raise_error
  end
end

RSpec.describe "document lifetime in C (TODO.perf/12)" do
  it "creates documents through the C factory with full surface" do
    doc = Leptris::XML::Document.create
    doc.root = doc.create_element("r")
    doc.root.add_child(doc.create_text_node("t"))
    expect(doc.to_xml).to eq(%q{<?xml version="1.0"?><r>t</r>})
    expect(doc.freed?).to be(false)
    doc.free
    expect(doc.freed?).to be(true)
    expect(doc.c_ptr).to be_nil
  end

  it "releases parsed documents at GC through the TypedData handle" do
    3_000.times { Leptris::XML::Document.parse(%q{<r><a x="1">t</a></r>}) }
    GC.start
    GC.start
  end

  it "never double-frees: explicit free then GC" do
    doc = Leptris::XML::Document.parse(%q{<r/>})
    doc.free
    GC.start
    expect(doc.freed?).to be(true)
  end
end
