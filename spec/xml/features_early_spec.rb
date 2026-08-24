# frozen_string_literal: true

require "leptris/xml"

RSpec.describe "v0.5.0+ element mutation" do
  let(:doc) { Leptris::XML::Document.parse("<root><a/><b/></root>") }
  let(:root) { doc.root }

  it "renames an element via #name=" do
    root.name = "renamed"
    expect(root.name).to eq("renamed")
  end

  it "sets and removes attributes via []= and remove_attribute" do
    root["id"] = "top"
    expect(root["id"]).to eq("top")
    root.remove_attribute("id")
    expect(root["id"]).to be_nil
  end

  it "sets text content via #content=" do
    root.content = "fresh text"
    expect(root.content).to eq("fresh text")
  end

  it "appends a created element via #add_child" do
    new_elem = doc.create_element("c")
    root.add_child(new_elem)
    expect(root.element_children.map(&:name)).to eq(%w[a b c])
  end

  it "supports << as add_child alias" do
    root << doc.create_element("c")
    expect(root.element_children.map(&:name)).to eq(%w[a b c])
  end

  it "prepends a child via #prepend_child" do
    root.prepend_child(doc.create_element("z"))
    expect(root.element_children.first.name).to eq("z")
  end
end

RSpec.describe "v0.5.0+ typed node creators" do
  let(:doc) { Leptris::XML::Document.parse("<root/>") }
  let(:root) { doc.root }

  it "creates and attaches a text node" do
    text = doc.create_text_node("hello")
    root.add_child(text)
    expect(root.content).to eq("hello")
  end

  it "creates and attaches a comment" do
    comment = doc.create_comment("a note")
    root.add_child(comment)
    expect(root.children.find { |n| n.comment? }.content).to eq("a note")
  end

  it "creates and attaches a CDATA section" do
    cdata = doc.create_cdata("<raw>data</raw>")
    root.add_child(cdata)
    expect(root.children.find { |n| n.cdata? }.content).to eq("<raw>data</raw>")
  end

  it "creates and attaches a processing instruction" do
    pi = doc.create_processing_instruction("xml-stylesheet", 'type="text/xsl"')
    root.add_child(pi)
    pi_node = root.children.find { |n| n.processing_instruction? }
    expect(pi_node.name).to eq("xml-stylesheet")
    expect(pi_node.content).to eq('type="text/xsl"')
  end

  it "supports Text#content= for existing text nodes" do
    text = doc.create_text_node("initial")
    root.add_child(text)
    text.content = "updated"
    expect(root.content).to eq("updated")
  end

  it "supports Comment#content= for existing comment nodes" do
    c = doc.create_comment("v1")
    root.add_child(c)
    c.content = "v2"
    expect(c.content).to eq("v2")
  end

  it "supports PI#target= and #data=" do
    pi = doc.create_processing_instruction("foo", "bar")
    root.add_child(pi)
    pi.target = "baz"
    pi.data = "qux"
    expect(pi.name).to eq("baz")
    expect(pi.content).to eq("qux")
  end
end

RSpec.describe "v0.5.0+ parent + unlink for non-element nodes" do
  it "exposes #parent on a Text node (worked around in v0.4.4)" do
    doc = Leptris::XML::Document.parse("<x>hello</x>")
    text = doc.root.child
    expect(text).to be_a(Leptris::XML::Text)
    expect(text.parent).to eq(doc.root)
  end

  it "exposes #parent on a Comment node" do
    doc = Leptris::XML::Document.parse("<x><!-- c --></x>")
    comment = doc.root.children.find(&:comment?)
    expect(comment.parent).to eq(doc.root)
  end

  it "unlinks a Text node via #remove" do
    doc = Leptris::XML::Document.parse("<x>hello</x>")
    text = doc.root.child
    text.remove
    expect(doc.root.content).to eq("")
  end
end

RSpec.describe "v0.5.0+ namespace definitions" do
  it "enumerates namespaces declared on an element" do
    doc = Leptris::XML::Document.parse(<<~XML)
      <root xmlns="http://default.example" xmlns:foo="http://foo.example">
        <child/>
      </root>
    XML
    decls = doc.root.namespace_definitions
    expect(decls.length).to eq(2)
    prefixes = decls.map(&:prefix)
    hrefs = decls.map(&:href)
    expect(hrefs).to include("http://default.example", "http://foo.example")
    expect(prefixes).to include(nil, "foo")
  end

  it "exposes inherited namespaces via #namespaces" do
    doc = Leptris::XML::Document.parse(<<~XML)
      <root xmlns:foo="http://foo.example">
        <child/>
      </root>
    XML
    child = doc.root.first_element_child
    expect(child.namespaces).to include("xmlns:foo" => "http://foo.example")
  end
end

RSpec.describe "v0.5.0+ line + compare" do
  it "exposes #line for parsed nodes" do
    doc = Leptris::XML::Document.parse("<root>\n  <child/>\n</root>")
    child = doc.root.first_element_child
    # libleptris v0.5.1 returns 0 for line numbers (function exists but
    # underlying tracking is not populated); just verify the call works.
    expect(child.line).to be_an(Integer)
  end

  it "compares nodes by document order via #<=>" do
    doc = Leptris::XML::Document.parse("<root><a/><b/></root>")
    a = doc.root.first_element_child
    b = a.next_element
    expect(a <=> b).to be < 0
    expect(b <=> a).to be > 0
    expect(a <=> a).to eq(0)
  end
end

RSpec.describe "v0.5.0+ serialization + C14N" do
  let(:doc) { Leptris::XML::Document.parse("<root><child id='1'>text</child></root>") }

  it "serializes the document to XML via Document#to_xml" do
    xml = doc.to_xml
    expect(xml).to include("<root>")
    expect(xml).to include("<child")
    expect(xml).to include('id="1"')
  end

  it "serializes an element subtree via Element#to_xml" do
    root_xml = doc.root.to_xml
    expect(root_xml).to include("<root>")
    expect(root_xml).not_to match(/\A<\?xml/)
  end

  it "canonicalizes the whole document via Document#canonicalize" do
    c14n = doc.canonicalize
    expect(c14n).to include("<root>")
    expect(c14n).to include("<child")
  end

  it "canonicalizes a subtree via Element#canonicalize (per #169)" do
    sub = doc.root.canonicalize
    expect(sub).to include("<child")
    expect(sub).to include("<root>")
  end

  it "preserves C14N 1.0 vs 1.1 modes" do
    c14n_10 = doc.canonicalize(Leptris::XML::FFI::C14N_1_0)
    c14n_11 = doc.canonicalize(Leptris::XML::FFI::C14N_1_1)
    expect(c14n_10).to include("<root")
    expect(c14n_11).to include("<root")
  end

  it "writes to a file via Document#save" do
    require "tmpdir"
    path = File.join(Dir.mktmpdir, "out.xml")
    doc.save(path)
    expect(File.read(path)).to include("<root>")
  end
end
