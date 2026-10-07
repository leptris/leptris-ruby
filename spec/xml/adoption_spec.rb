# frozen_string_literal: true

require "open3"
require "spec_helper"

# 1.9.304 / #1528: foreign nodes are ADOPTED BY COPY at the splice.
# The binding must return the INSTALLED wrapper — the original
# points at the detached source, which dies with its document
# (the xpath.rb:39 compiled-eval crash shape: scratch-doc markup
# appended into a live tree, scratch freed, next eval detonated).
RSpec.describe "cross-document adoption (#1528)" do
  it "add_child of a foreign node returns the installed copy" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<new attr="v">t</new>))
    foreign = scratch.root
    installed = doc.root.add_child(foreign)
    expect(installed.name).to eq("new")
    expect(installed["attr"]).to eq("v")
    expect(installed.content).to eq("t")
    expect(doc.root.element_children.first).to equal(installed)
    expect(foreign.document).to equal(scratch) # source untouched
  end

  it "the installed copy survives scratch-document free + eval" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(
      %(<new><cite key="k">A</cite></new>))
    installed = doc.root.add_child(scratch.root)
    scratch.free # the #1528 detonator
    expect(doc.xpath("//cite/@key").map(&:value)).to eq(%w[k])
    expect(installed.name).to eq("new")
    expect(doc.root.to_xml).to eq(%(<r><new><cite key="k">A</cite></new></r>))
  end

  it "append_children re-wraps installed copies for foreign batches" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<s><a>1</a><b>2</b></s>))
    kids = scratch.root.element_children.to_a
    installed = doc.root.append_children(kids)
    expect(installed.map(&:name)).to eq(%w[a b])
    scratch.free
    expect(doc.xpath("//a").first.content).to eq("1")
    expect(doc.xpath("//b").first.content).to eq("2")
  end

  it "children= replaces wholesale with foreign lists" do
    doc = Leptris::XML::Document.parse(%(<r><old/></r>))
    scratch = Leptris::XML::Document.parse(%(<s><n1/><n2/></s>))
    doc.root.children = scratch.root.element_children.to_a
    scratch.free
    expect(doc.xpath("//n1")).not_to be_empty
    expect(doc.xpath("//n2")).not_to be_empty
  end

  it "same-document appends stay pointer-identical" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    kid = doc.create_element("same")
    ret = doc.root.add_child(kid)
    expect(ret).to equal(kid)
    batch = [doc.create_element("b1"), doc.create_element("b2")]
    expect(doc.root.append_children(batch)).to equal(batch)
  end
end

# 1.9.307 (#1534): the #1528 adoption gate covered ELEMENT splices
# only — TEXT/CDATA/COMMENT/PI from a scratch document were still
# spliced raw. Leaves now adopt by copy too.
RSpec.describe "cross-document LEAF adoption (1.9.307, #1534)" do
  it "subtree adoption carries leaves; scratch free survives" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(
      %(<s><p>t1<c/></p><!-- note --><q><![CDATA[cd]]></q></s>))
    doc.root.add_child(scratch.root)
    scratch.free
    expect(doc.xpath("//p").first.content).to eq("t1")
    expect(doc.xpath("//q").first.children.first.content).to eq("cd")
    expect(doc.root.to_xml).to include("<!-- note -->")
  end

  it "adopted in-subtree leaves survive scratch free + eval (#1534)" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(
      %(<s><c>text &amp; more</c></s>))
    doc.root.add_child(scratch.root.element_children.first)
    scratch.free
    expect(doc.xpath("//c").first.content).to eq("text & more")
    expect(doc.root.to_xml).to include("text &amp; more")
  end

  it "add_child(String) fragment text survives the fragment lifetime" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    doc.root.add_child(%(<a>text & more</a>))
    expect(doc.xpath("//a").first.content).to eq("text & more")
    GC.start
    expect(doc.root.to_xml).to include("text &amp; more")
  end
end

# 1.9.311 (#1548): Document#absorb — move semantics for doomed
# splice sources. Absorbed splices move by reference (O(1), no
# copy); the source free is handle-only.
RSpec.describe "Document#absorb (1.9.311, #1548)" do
  it "absorbed splices move by reference and survive source free" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(
      %(<s><sec id="a"><p>text</p><c/></sec><sec id="b"/></s>))
    doc.absorb(scratch)
    a = scratch.root.element_children.first
    doc.root.add_child(a)
    scratch.free # handle-only
    expect(doc.xpath("//sec[@id='a']/p").first.content).to eq("text")
    expect(doc.root.to_xml).to include(%(<sec id="a">))
  end

  it "repeated absorbed splices all survive one source free" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(
      %(<s><i>1</i><i>2</i><i>3</i></s>))
    doc.absorb(scratch)
    scratch.root.element_children.to_a.each { |n| doc.root.add_child(n) }
    scratch.free
    expect(doc.xpath("//i").map(&:content)).to eq(%w[1 2 3])
  end

  it "rejects chaining and self-absorb" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<s/>))
    doc.absorb(scratch)
    expect { scratch.absorb(doc) }
      .to raise_error(Leptris::XML::Error, /argument|absorb/i)
    expect { doc.absorb(doc) }
      .to raise_error(Leptris::XML::Error, /argument/i)
  end

  it "splices into a THIRD document still deep-copy" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<s><x>v</x><y>w</y></s>))
    other = Leptris::XML::Document.parse(%(<o/>))
    doc.absorb(scratch)
    x, y = scratch.root.element_children.to_a
    other.root.add_child(x)   # third doc: deep copy, source removed
    doc.root.add_child(y)     # absorbed doc: move by reference
    scratch.free
    expect(other.xpath("//x").first.content).to eq("v")
    expect(doc.xpath("//y").first.content).to eq("w")
  end
end

# #376 shape 3: moxml's create_element hands the binding FLOATING
# (docless) wrappers — Node wrappers whose #document is nil but
# whose C node is live in a foreign pool. The adoption contract
# applies to them exactly as to attached-foreign nodes: the splice
# returns the INSTALLED copy, declarations ride the lift.
RSpec.describe "docless-child adoption (#376)" do
  def docless_element(doc, name)
    ptr = Leptris::XML::FFI.leptris_element_create(doc.c_ptr, name)
    Leptris::XML::Node.wrap_fresh(ptr, nil, Leptris::XML::FFI::NODE_ELEMENT)
  end

  it "add_child of a docless element returns the installed copy" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<s/>))
    floater = docless_element(scratch, "made")
    floater["id"] = "7"
    installed = doc.root.add_child(floater)
    expect(installed.name).to eq("made")
    expect(installed["id"]).to eq("7")
    expect(installed.document).to equal(doc)
    expect(installed.parent).to equal(doc.root)
    expect(doc.root.element_children.first).to equal(installed)
  end

  it "a docless element with a namespace keeps its declaration" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<s/>))
    attached = scratch.create_element("nsed")
    attached.add_namespace_definition("x", "urn:x")
    floater = Leptris::XML::Node.wrap_fresh(
      attached.c_ptr, nil, Leptris::XML::FFI::NODE_ELEMENT)
    expect(floater.document).to be_nil
    installed = doc.root.add_child(floater)
    expect(installed.name).to eq("nsed")
    expect(installed.namespace_definitions.map(&:href)).to eq(%w[urn:x])
    expect(doc.root.to_xml).to include(%(xmlns:x="urn:x"))
  end

  it "docless comment and processing-instruction children adopt" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<s/>))
    comment_ptr = Leptris::XML::FFI.leptris_document_add_comment(
      scratch.c_ptr, "note")
    floater = Leptris::XML::Node.wrap_fresh(
      comment_ptr, nil, Leptris::XML::FFI::NODE_COMMENT)
    installed = doc.root.add_child(floater)
    expect(installed.comment?).to eq(true)
    expect(installed.content).to eq("note")
    expect(installed.document).to equal(doc)
    expect(doc.root.to_xml).to eq(%(<r><!--note--></r>))
  end

  it "append_children returns installed copies for docless batches" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<s/>))
    floaters = %w[a1 a2].map { |n| docless_element(scratch, n) }
    installed = doc.root.append_children(floaters)
    expect(installed.map(&:name)).to eq(%w[a1 a2])
    expect(installed.map(&:document).uniq).to eq([doc])
    expect(doc.root.element_children.map(&:name)).to eq(%w[a1 a2])
  end

  it "prepend_child and sibling inserts return installed positions" do
    doc = Leptris::XML::Document.parse(%(<r><keep/></r>))
    scratch = Leptris::XML::Document.parse(%(<s/>))
    first = docless_element(scratch, "lead")
    installed = doc.root.prepend_child(first)
    expect(installed.name).to eq("lead")
    expect(doc.root.element_children.first).to equal(installed)

    anchor = doc.root.element_children.last
    after = docless_element(scratch, "tail")
    nxt = anchor.add_next_sibling(after)
    expect(nxt.name).to eq("tail")
    expect(anchor.next_sibling).to equal(nxt)

    before = docless_element(scratch, "head")
    prev = anchor.add_previous_sibling(before)
    expect(prev.name).to eq("head")
    expect(anchor.previous_sibling).to equal(prev)
  end

  it "root= of a docless element installs a proper copy" do
    doc = Leptris::XML::Document.create
    scratch = Leptris::XML::Document.parse(%(<s/>))
    floater = docless_element(scratch, "made")
    floater["id"] = "9"
    doc.root = floater
    expect(doc.root.name).to eq("made")
    expect(doc.root.document).to equal(doc)
    # writes through the destination must land in the destination
    doc.root["k"] = "v"
    expect(doc.root["k"]).to eq("v")
    expect(doc.root.to_xml).to eq(%(<made id="9" k="v"/>))
    scratch.free
    expect(doc.root.to_xml).to eq(%(<made id="9" k="v"/>))
  end
end

# #386: the absorb contract permits sources that stay ALIVE — a
# library that pins adopted-source documents (moxml's lifetime
# pins) keeps their handles past the destination's release, so
# every finalization path must know the pool moved: the C
# lifetime handle's dfree and the no-native Ruby finalizer.
# Subprocess: the abort fires at exit-time finalization, which an
# in-process suite cannot observe.
RSpec.describe "absorbed-source exit finalization (#386)" do
  REPRO = <<~'RUBY'
    require "leptris"
    doc = Leptris::XML::Document.parse("<r/>")
    pinned = []
    50.times do |i|
      scratch = Leptris::XML::Document.parse("<s#{i}><x v='1'>t</x></s#{i}>")
      doc.absorb(scratch)
      doc.root.add_child(scratch.root.element_children.first)
      pinned << scratch
      GC.start
    end
    puts "done"
  RUBY

  it "does not double-free the transferred pool (native path)" do
    lib = File.expand_path("../../lib", __dir__)
    out, status = Open3.capture2e(RbConfig.ruby, "-I", lib, "-e", REPRO)
    expect(status).to be_success
    expect(out).to include("done")
  end

  it "does not double-free the transferred pool (FFI finalizer path)" do
    lib = File.expand_path("../../lib", __dir__)
    out, status = Open3.capture2e(
      { "LEPTRIS_NO_NATIVE" => "1" }, RbConfig.ruby, "-I", lib, "-e", REPRO)
    expect(status).to be_success
    expect(out).to include("done")
  end
end

# Engine 1.9.312 (#1539): a leaf sitting directly on a scratch
# document's children chain (prolog comment / PI) adopts
# single-node on cross-document append — the chain copier
# previously misread the root element as OOM
# (LEPTRIS_ERROR_MEMORY).
RSpec.describe "root-level leaf splice (#1539)" do
  it "adopts a prolog comment from a scratch document" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(
      %(<?xml version="1.0"?><!--note--><s/>))
    leaf = scratch.children.first
    expect(leaf).to be_a(Leptris::XML::Comment)
    installed = doc.root.add_child(leaf)
    expect(installed.comment?).to eq(true)
    expect(doc.root.to_xml).to eq(%(<r><!--note--></r>))
    scratch.free
    expect(doc.root.to_xml).to eq(%(<r><!--note--></r>))
  end
end

# Engine 1.9.313 (#1557): absorption-aware release at the C ABI.
# The anchor dying while the source handle is still outstanding
# defers the pool release to that handle's free (absorbed_deferred)
# instead of clearing the state — the holder's free performs the
# full release, handles released before the anchor keep the
# handle-only no-op. The binding's #386 mitigation stays as
# defense-in-depth; this pins the engine-side contract.
RSpec.describe "absorbed-source release ordering (#1557)" do
  it "anchor freed first, holder freed after — no double release" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<s><x>v</x></s>))
    doc.absorb(scratch)
    doc.root.add_child(scratch.root.element_children.first)
    expect(doc.root.to_xml).to eq(%(<r><x>v</x></r>))
    doc.free
    scratch.free
    GC.start
    expect(true).to eq(true) # reaching here is the contract — no abort
  end

  it "handle released before the anchor keeps the no-op shape" do
    doc = Leptris::XML::Document.parse(%(<r/>))
    scratch = Leptris::XML::Document.parse(%(<s/>))
    doc.absorb(scratch)
    scratch.free # holder first: handle-only
    doc.free
    GC.start
    expect(true).to eq(true)
  end
end
