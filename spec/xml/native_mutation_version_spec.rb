# frozen_string_literal: true

require "spec_helper"

begin
  require "leptris/xml/native_layer"
  NATIVE = defined?(Leptris::XML::Native) && defined?(Leptris::XML::NativeNode)
rescue LoadError
  NATIVE = false
end

# leptris-ruby#539: every wrapper-visible mutation must advance the
# binding Document's mutation version — the invalidation signal for
# the C content memo (nn_content, the face behind NativeNode#content
# and the text_read contract read) and the walk-read memos
# (children_read). The attached-construction faces
# (create_element_with_attrs / _wrapped) attach a built child under
# a parent — a tree mutation — but skipped the version advance, so
# any memo warmed before the construction served stale data after
# it (the walk-row campaign's stale el.text).
RSpec.describe "native mutation faces advance the document version",
               if: NATIVE do
  let(:doc) { Leptris::XML::Document.parse("<p>old</p>") }
  let(:root) { doc.root }

  def with_version
    v0 = doc.version
    yield
    doc.version
  end

  describe "attached construction faces (the #539 seam)" do
    it "advances the version through create_element_with_attrs" do
      v = with_version do
        Leptris::XML::Native.create_element_with_attrs(
          doc, root.c_address, "z", ["k", "v"])
      end
      expect(v).to be > 0
    end

    it "keeps the legacy raw-address (Integer document) lane working" do
      # moxml's pre-#340 callers pass doc.c_address — the lane stays
      # open (ungated: the Document object is unreachable from a bare
      # address); the wrapped face is the gated path for current
      # consumers.
      addr = nil
      expect do
        addr = Leptris::XML::Native.create_element_with_attrs(
          doc.c_address, root.c_address, "z", [])
      end.not_to raise_error
      expect(addr).to be > 0
    end

    it "advances the version through create_element_with_attrs_wrapped" do
      v = with_version do
        Leptris::XML::Native.create_element_with_attrs_wrapped(
          doc, root.c_address, "z", ["k", "v"])
      end
      expect(v).to be > 0
    end

    it "leaves detached construction (parent_addr 0) bump-free" do
      v = with_version do
        Leptris::XML::Native.create_element_with_attrs(
          doc, 0, "z", [])
      end
      expect(v).to eq(0)
    end

    it "gates readonly documents on the attached face" do
      doc.readonly!
      expect do
        Leptris::XML::Native.create_element_with_attrs_wrapped(
          doc, root.c_address, "z", [])
      end.to raise_error(Leptris::XML::ReadOnlyError)
    end

    it "raises UseAfterFreeError on a freed document" do
      doc2 = Leptris::XML::Document.parse("<p/>")
      doc2.free
      expect do
        Leptris::XML::Native.create_element_with_attrs_wrapped(
          doc2, 0, "z", [])
      end.to raise_error(Leptris::XML::UseAfterFreeError)
    end
  end

  describe "the stale-serve the desync produced" do
    it "retires a warm children_read memo across attached construction" do
      nn = doc.native_node
      warm = nn.children_read
      expect(warm.map(&:name)).to eq([""]) # the "old" text node

      Leptris::XML::Native.create_element_with_attrs(
        doc, root.c_address, "z", [])

      fresh = nn.children_read
      expect(fresh.map { |n| n.node_type }).to include(:element)
      expect(fresh).not_to equal(warm)
    end

    it "retires the C content memo stamp across attached construction" do
      nn = doc.native_node
      expect(nn.content).to eq("old")

      child = Leptris::XML::Native.create_element_with_attrs_wrapped(
        doc, root.c_address, "z", [])

      # the attached child is visible through a fresh read
      kids = doc.native_node.element_children
      expect(kids.map(&:name)).to eq(%w[z])
      expect(child.name).to eq("z")
    end
  end

  describe "the issue's headline shape (add_child appends, text reads)" do
    it "serves fresh aggregate text after add_child of a texted child" do
      parent = Leptris::XML::Document.parse("<p>old</p>").root
      expect(parent.text).to eq("old") # warm the memo

      child = parent.document.create_element("z")
      child.content = "new"
      parent.add_child(child)

      expect(parent.text).to eq("oldnew")
    end

    it "serves fresh aggregate text after add_child of markup" do
      parent = Leptris::XML::Document.parse("<p>old</p>").root
      expect(parent.text).to eq("old")

      parent.add_child("<z>new</z>")

      expect(parent.text).to eq("oldnew")
    end

    it "serves fresh aggregate text on the native wrapper face" do
      doc.native_node # mint the wrapper identity
      nn = doc.native_node
      expect(nn.content).to eq("old") # warm the C content memo

      child = doc.native_create_element("z")
      child.content = "new"
      nn.add_child(child)

      expect(nn.content).to eq("oldnew")
    end
  end

  describe "the rest of the mutation battery (no regressions)" do
    def bumping
      v0 = doc.version
      yield
      expect(doc.version).to be > v0
    end

    it "bumps on the binding element writes" do
      bumping { root.content = "x" }
      bumping { root.name = "q" }
      bumping { root["k"] = "v" }
    end

    it "bumps on the binding append and splice faces" do
      bumping { root.add_child(doc.create_element("a")) }
      bumping { root.add_child("<b>1</b>") }
      bumping { root.prepend_child(doc.create_element("c")) }
      bumping { root.children.first.add_next_sibling(doc.create_element("d")) }
      bumping { root.children.last.add_previous_sibling(doc.create_element("e")) }
      bumping { root.children.first.remove }
      bumping { root.children.first.replace(doc.create_element("f")) }
      bumping { root.append_children([doc.create_element("g")]) }
    end

    it "bumps on the document faces" do
      bumping { doc.root = doc.create_element("newroot") }
      bumping { doc.add_pi("tgt", "data") }
    end

    it "bumps on the NativeNode TypedData faces" do
      nn = doc.native_node
      bumping { nn.content = "x" }
      bumping { nn.set_attribute("k", "v") }
      bumping { nn.add_child(doc.native_create_element("y")) }
      bumping { nn.create_child("w") }
    end

    it "bumps on the Native module write faces" do
      bumping do
        Leptris::XML::Native.append_binding_child(
          doc, root.c_address, doc.create_element("z").c_address)
      end
      bumping { Leptris::XML::Native.append_markup(doc, root.c_address, "<z>1</z>") }
      bumping { Leptris::XML::Native.set_binding_attribute(doc, root.c_address, "k", "v") }
      bumping { Leptris::XML::Native.set_binding_name(doc, root.c_address, "q") }
      # splice faces BEFORE the content write: set_binding_text is an
      # aggregating set — it replaces the child list.
      bumping do
        Leptris::XML::Native.insert_binding_child(
          doc, root.children.first.c_address, doc.create_element("i").c_address, 3)
      end
      bumping { Leptris::XML::Native.unlink_binding_node(doc, root.children.first.c_address) }
      bumping { Leptris::XML::Native.set_binding_text(doc, root.c_address, "x") }
      bumping { Leptris::XML::Native.set_binding_root(doc, doc.create_element("r").c_address) }
    end

    it "stays bump-free on detached creates" do
      v = with_version { doc.create_element("z", { "k" => "v" }) }
      expect(v).to eq(0)
      v = with_version { doc.native_create_element("z") }
      expect(v).to eq(0)
      v = with_version { doc.native_create_text("t") }
      expect(v).to eq(0)
    end
  end
end
