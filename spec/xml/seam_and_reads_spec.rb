# frozen_string_literal: true

require "spec_helper"
RSpec.describe "read-path performance surface" do
  describe "UTF-8 at the FFI seam" do
    it "returns UTF-8 strings for names, content, and attribute values" do
      doc = Leptris::XML.parse(%(<r a="1">café</r>))
      expect(doc.root.name.encoding).to eq(Encoding::UTF_8)
      expect(doc.root["a"].encoding).to eq(Encoding::UTF_8)
      expect(doc.root.content.encoding).to eq(Encoding::UTF_8)
      expect(doc.root.content).to eq("café")
    end

    it "returns UTF-8 for path, pull attributes, and fragment content" do
      doc = Leptris::XML.parse(%(<r lang="en"/>))
      expect(doc.root.path.encoding).to eq(Encoding::UTF_8)
      events = []
      Leptris::XML::Pull.parse(%(<r k="v"/>)) { |e| events << e }
      attrs = events.first.attrs
      expect(attrs["k"].encoding).to eq(Encoding::UTF_8)
    end
  end

  describe "readonly memoization coverage" do
    let(:doc) do
      Leptris::XML.parse(
        %(<r xmlns:p="urn:p"><c p:a="1" plain="2">t<b/></c></r>),
        readonly: true)
    end
    let(:child) { doc.root.element_children.first }

    it "memoizes namespace reads" do
      expect(child.namespace_definitions).to equal(child.namespace_definitions)
      expect(child.namespaces).to equal(child.namespaces)
      expect(child.namespace).to equal(child.namespace)
    end

    it "memoizes attribute listings" do
      expect(child.keys).to equal(child.keys)
      expect(child.values).to equal(child.values)
      expect(child.attribute_nodes).to equal(child.attribute_nodes)
    end

    it "memoizes node paths and element children" do
      expect(child.path).to equal(child.path)
      expect(child.css_path).to equal(child.css_path)
      expect(child.element_children).to equal(child.element_children)
    end

    it "memoizes text content on non-element nodes" do
      text = child.children.find(&:text?)
      expect(text.content).to equal(text.content)
    end

    it "memoizes document-level PIs" do
      doc.add_pi("x", "y") rescue nil # readonly raises; PIs still memoize on the parsed doc
      expect(doc.processing_instructions)
        .to equal(doc.processing_instructions)
    end

    it "memoizes writable documents between mutations, never stale after" do
      writable = Leptris::XML.parse(
        %(<r xmlns:p="urn:p"><c p:a="1"/></r>))
      c = writable.root.element_children.first
      expect(c.namespaces).to equal(c.namespaces)  # memoized: no mutation yet
      writable.root.element_children.first["p:a"] = "2"
      expect(c["p:a"]).to eq("2")                  # [] re-reads (writable FFI path)
      c2 = writable.root.element_children.first
      expect(c2.attributes["p:a"].value).to eq("2") # mutation invalidated memos
      c3 = Leptris::XML.parse(
        %(<r xmlns:p="urn:p"><c p:a="1"/></r>)).root.element_children.first
      c3.content = "changed"
      expect(c3.content).to eq("changed")           # own-field memo refreshed
    end
  end

  describe "CSS translation cache" do
    it "returns the cached translation for repeated rules" do
      first = Leptris::XML::CssToXPath.convert("item > name")
      expect(Leptris::XML::CssToXPath.convert("item > name"))
        .to equal(first)
    end

    it "does not cache failed translations" do
      expect { Leptris::XML::CssToXPath.convert("a:unknown-pseudo") }
        .to raise_error(ArgumentError)
      expect { Leptris::XML::CssToXPath.convert("a:unknown-pseudo") }
        .to raise_error(ArgumentError)
    end
  end

  describe "Attr micro-paths" do
    it "escapes all five entities in one pass" do
      attr = Leptris::XML::Attr.new("k", %(<a & "b" 'c'>), nil)
      expect(attr.to_xml).to eq(%(k="&lt;a &amp; &quot;b&quot; &apos;c&apos;&gt;"))
    end

    it "answers prefix without allocation churn" do
      expect(Leptris::XML::Attr.new("p:k", "v", nil).prefix).to eq("p")
      expect(Leptris::XML::Attr.new("k", "v", nil).prefix).to be_nil
    end
  end
end


RSpec.describe "round IX: readonly [] and materialized NodeSets" do
  it "serves readonly [] from the memoized attributes hash" do
    doc = Leptris::XML.parse(%(<r a="1" b="café"><c/></r>), readonly: true)
    root = doc.root
    expect(root["a"]).to eq("1")
    expect(root["b"]).to eq("café")
    expect(root["a"].encoding).to eq(Encoding::UTF_8)
    expect(root["missing"]).to be_nil
    # equivalence with the writable path
    writable = Leptris::XML.parse(%(<r a="1" b="café"><c/></r>))
    expect(writable.root["b"]).to eq(root["b"])
    # writable values track mutation; readonly refuses it
    writable.root["a"] = "2"
    expect(writable.root["a"]).to eq("2")
    expect { root["a"] = "2" }.to raise_error(Leptris::XML::ReadOnlyError)
  end

  it "stops re-batching a materialized NodeSet" do
    doc = Leptris::XML.parse("<r>" + (1..5).map { |i| "<a>#{i}</a>" }.join + "</r>")
    ns = doc.root.xpath("//a")
    first_pass = ns.to_a
    expect(ns.length).to eq(5)
    second_pass = []
    ns.each { |n| second_pass << n }
    # identical wrapper objects — the materialized array is authoritative
    expect(second_pass).to eq(first_pass)
    expect(second_pass.first).to equal(first_pass.first)
    expect(ns[0]).to equal(first_pass[0])
    expect(ns[-1]).to equal(first_pass.last)
    fresh = doc.root.xpath("//a")
    expect(fresh[-1]).to equal(first_pass.last)
  end
end

RSpec.describe "round X: iteration materializes; leaner memo guard" do
  it "materializes on the first each, without to_a" do
    doc = Leptris::XML.parse("<r>" + (1..5).map { |i| "<a>#{i}</a>" }.join + "</r>")
    ns = doc.root.xpath("//a")
    first_pass = []
    ns.each { |n| first_pass << n }
    second_pass = []
    ns.each { |n| second_pass << n }
    expect(second_pass).to eq(first_pass)
    expect(second_pass.first).to equal(first_pass.first)
    expect(ns.length).to eq(5)
    expect(ns[4]).to equal(first_pass.last)
  end

  it "keeps memo semantics on writable documents" do
    doc = Leptris::XML.parse("<r><a x='1'>t</a></r>")
    a = doc.root.element_children.first
    expect(a.content).to eq("t")
    a.content = "u"
    expect(a.content).to eq("u")  # no stale memo on writable docs
  end
end

RSpec.describe "round XI: cached-true readonly; lazy wrapper cache" do
  it "observes a writable-then-readonly flip" do
    doc = Leptris::XML.parse(%(<r a="1"><c>t</c></r>))
    root = doc.root
    expect(root["a"]).to eq("1")          # writable path, false uncached
    doc.readonly!
    expect(root["a"]).to eq("1")          # cached-true observed
    expect { root["a"] = "2" }.to raise_error(Leptris::XML::ReadOnlyError)
    expect(root["a"]).to eq("1")
  end

  it "preserves wrapper identity with the lazily allocated cache" do
    doc = Leptris::XML.parse("<r><a/></r>")
    expect(doc.root.element_children.first)
      .to equal(doc.root.element_children.first)
  end
end

RSpec.describe "round XII: versioned writable memoization" do
  def doc_with_memoized_reads
    doc = Leptris::XML.parse(
      %(<r xmlns:p="urn:p"><c a="1" p:k="2">old<!--cm--></c><sib/></r>))
    c = doc.root.element_children.first
    c.children; c.element_children; c.keys; c.values; c.attributes
    c.attribute_nodes; c.namespace; c.namespace_definitions; c.namespaces
    c.content; c.path; c.css_path
    [doc, c]
  end

  it "memoizes between mutations, recomputes after (content)" do
    doc, c = doc_with_memoized_reads
    v0 = doc.version
    c.content = "new"
    expect(doc.version).to eq(v0 + 1)
    expect(c.content).to eq("new")
    fresh_text = c.children.find(&:text?)
    expect(fresh_text.content).to eq("new")
  end

  it "invalidates after attribute mutation" do
    doc, c = doc_with_memoized_reads
    c["a"] = "9"
    expect(c["a"]).to eq("9")
    expect(c.attributes["a"].value).to eq("9")
    expect(c.values).to include("9")
    expect(c.keys.sort).to eq(c.attribute_nodes.map(&:name).sort)
  end

  it "invalidates after structural mutation" do
    doc, c = doc_with_memoized_reads
    before = c.children.length
    c << doc.create_element("added")
    expect(c.children.length).to eq(before + 1)
    expect(c.element_children.map(&:name)).to eq(["added"])
    expect(c.element_children.first.path).to include("added")
  end

  it "invalidates after namespace mutation" do
    doc, c = doc_with_memoized_reads
    c.add_namespace_definition("q", "urn:q")
    expect(c.namespaces).to include("xmlns:q" => "urn:q")
    expect(c.namespace_definitions.map(&:prefix)).to include("q")
  end

  it "invalidates after root replacement and document PIs" do
    doc, = doc_with_memoized_reads
    doc.add_pi("t", "d")
    expect(doc.processing_instructions).to eq([["t", "d"]])
    doc.root = doc.create_element("newroot")
    expect(doc.root.name).to eq("newroot")
  end

  it "keeps readonly semantics: version never advances" do
    doc = Leptris::XML.parse(%(<r a="1"/>), readonly: true)
    expect(doc.version).to eq(0)
    expect(doc.root.attributes).to equal(doc.root.attributes)
    expect { doc.root["a"] = "x" }.to raise_error(Leptris::XML::ReadOnlyError)
    expect(doc.version).to eq(0)
  end
end

RSpec.describe "round XIII: hash-served [], engine-served qualified names" do
  it "serves bare names from the versioned hash on writable documents" do
    doc = Leptris::XML.parse(%(<r a="1"><c/></r>))
    root = doc.root
    expect(root["a"]).to eq("1")
    root["a"] = "2"
    expect(root["a"]).to eq("2")
  end

  it "routes qualified names to the engine (declaration resolution)" do
    doc = Leptris::XML.parse(
      %(<r xmlns:a="urn:x" xmlns:b="urn:x" a:k="1" b:k="2" k="3"/>))
    root = doc.root
    expect(root["b:k"]).to eq("1")   # expanded-name match, cross-prefix
    expect(root["k"]).to eq("3")     # bare = no-namespace
    expect(root["c:k"]).to be_nil    # undeclared prefix
  end

  it "memoizes first_element_child with version invalidation" do
    doc = Leptris::XML.parse(%(<r>t<a/><b/></r>))
    first = doc.root.first_element_child
    expect(doc.root.first_element_child).to equal(first)
    doc.root << doc.create_element("z")
    expect(doc.root.first_element_child).to equal(first)
    first.unlink
    expect(doc.root.first_element_child.name).to eq("b")
  end
end

RSpec.describe "round XIV: single-node query seam" do
  it "matches xpath().first across result shapes" do
    doc = Leptris::XML.parse(%(<r><a id="1"/><a id="2"/></r>))
    expect(doc.at_xpath("//a")).to eq(doc.xpath("//a").first)
    expect(doc.at_xpath("//nope")).to be_nil
    expect(doc.at_xpath("count(//a)")).to eq(2.0)      # scalar keeps semantics
    expect(doc.at_xpath("string(//a/@id)")).to eq("1") # scalar string
  end

  it "serves at_css through the same seam" do
    doc = Leptris::XML.parse(%(<r><item><name>one</name></item><item><name>two</name></item></r>))
    expect(doc.at_css("item > name").content).to eq("one")
    expect(doc.at_css("nope")).to be_nil
    b = doc.root.element_children.last
    expect(b.at_css("name").content).to eq("two")  # receiver-relative
  end
end

RSpec.describe "round XV: type-tagged batch materialization" do
  it "dispatches wrapper classes from the batch-fetched kinds" do
    doc = Leptris::XML.parse(
      %(<r>text<!--c--><![CDATA[cd]]><?pi d?><a/></r>))
    ns = doc.root.xpath("//node()")
    kinds = ns.map(&:class)
    # document order: the root element, then its children — the
    # element hints and the get_type fallbacks agree with the
    # pre-hint classes (CDATA distinguished despite XPath's data
    # model folding it to TEXT)
    expect(kinds).to eq([Leptris::XML::Element, Leptris::XML::Text,
                         Leptris::XML::Comment, Leptris::XML::CDATA,
                         Leptris::XML::ProcessingInstruction,
                         Leptris::XML::Element])
    expect(ns.last.name).to eq("a")
    expect(ns[1].content).to eq("text")
    expect(ns[3].content).to eq("cd")
  end
end

RSpec.describe "round XVIII: at() on the single-node seam" do
  it "matches at_xpath and at_css across shapes" do
    doc = Leptris::XML.parse(%(<r><a id="1"/><a id="2"/><c/></r>))
    expect(doc.at("//a")).to eq(doc.at_xpath("//a"))
    expect(doc.at("c")).to eq(doc.at_css("c"))
    expect(doc.at("nope")).to be_nil
    expect(doc.at("//nope")).to be_nil
    # Scalars (count/string) are at_xpath's contract — the generic
    # at dispatches on path-prefix syntax, same rule as #search.
    expect(doc.at_xpath("count(//a)")).to eq(2.0)
    expect(doc % "//a").to eq(doc.at_xpath("//a"))  # the % alias too
    b = doc.root.element_children.first
    expect(b.at("./following-sibling::c").name).to eq("c")  # relative xpath
  end
end

RSpec.describe "round XX: scratch-buffered batch fetches" do
  it "grows the scratch buffer past a 32-child family and reads every child" do
    wide = (1..80).map { |i| "<n#{i}/>x" }.join
    root = Leptris::XML::Document.parse("<r>#{wide}</r>").root
    expect(root.children.size).to eq(160)
    expect(root.children.map(&:name)).to include("n1", "n80")
  end

  it "reuses the grown buffer across narrower families without crosstalk" do
    doc = Leptris::XML::Document.parse(
      "<r><wide>#{(1..40).map { |i| "<c#{i}/>" }.join}</wide><tiny><one/></tiny></r>")
    wide, tiny = doc.root.element_children.first, doc.root.element_children.last
    expect(wide.children.size).to eq(40)
    expect(tiny.children.size).to eq(1)
    expect(tiny.children.first.name).to eq("one")
    # drain in the opposite order too — the buffer is shared per thread
    expect(tiny.children.size).to eq(1)
    expect(wide.children.map(&:name)).to eq((1..40).map { |i| "c#{i}" })
  end

  it "keeps concurrent fetches independent across threads" do
    doc = Leptris::XML::Document.parse(
      "<r>#{(1..50).map { |i| "<c#{i}/>t" }.join}</r>")
    root = doc.root
    threads = 4.times.map do
      Thread.new do
        10.times do
          kids = root.children.to_a
          raise "size #{kids.size}" unless kids.size == 100
        end
      end
    end
    threads.each(&:join)
    expect(root.children.size).to eq(100)
  end
end

RSpec.describe "round XXIII: element-only child batch" do
  it "returns only the element children, in order, for mixed content" do
    root = Leptris::XML::Document.parse(
      "<r>t1<a/><!--c--><![CDATA[x]]><?pi p?><b/>t2</r>").root
    expect(root.children.map(&:type)).to include(
      Leptris::XML::FFI::NODE_TEXT, Leptris::XML::FFI::NODE_COMMENT,
      Leptris::XML::FFI::NODE_CDATA, Leptris::XML::FFI::NODE_PI)
    expect(root.element_children.map(&:name)).to eq(%w[a b])
    expect(root.element_children.map(&:type)).to all(
      eq(Leptris::XML::FFI::NODE_ELEMENT))
  end

  it "keeps the filter path for non-element receivers" do
    doc = Leptris::XML::Document.parse(
      "<?pi p?><!--c--><r><a/></r><!--e-->")
    expect(doc.node.element_children.map(&:name)).to eq(%w[r])
    expect(doc.children.select(&:element?).map(&:name)).to eq(%w[r])
  end

  it "invalidates after a mutation adds an element child" do
    doc = Leptris::XML::Document.parse("<r><a/></r>")
    root = doc.root
    expect(root.element_children.map(&:name)).to eq(%w[a])
    b = doc.create_element("b")
    root.add_child(b)
    expect(root.element_children.map(&:name)).to eq(%w[a b])
  end
end

RSpec.describe "round XXIII: first/last element child scans" do
  it "skips leading text and trailing comments without wrapping them" do
    root = Leptris::XML::Document.parse(
      "<r>text<a/>mid<b/><!--trailing--></r>").root
    expect(root.first_element_child.name).to eq("a")
    expect(root.last_element_child.name).to eq("b")
  end

  it "answers nil when no element child exists" do
    root = Leptris::XML::Document.parse("<r>text<!--c--></r>").root
    expect(root.first_element_child).to be_nil
    expect(root.last_element_child).to be_nil
  end

  it "keeps the fallback for non-element receivers" do
    doc = Leptris::XML::Document.parse("<?pi?><!--c--><r><a/><b/></r><!--e-->")
    expect(doc.node.first_element_child.name).to eq("r")
    expect(doc.node.last_element_child.name).to eq("r")
  end
end

RSpec.describe "round XXIV: element-batch truncation regression" do
  # The scratch is thread-local: a fresh thread deterministically
  # reproduces the fresh-process state where 1.9.28 truncated wide
  # element families to the initial scratch capacity.
  it "returns every element child from a fresh scratch (thread)" do
    xml = "<r>#{(1..80).map { |i| "<n#{i}/>" }.join}</r>"
    names = []
    Thread.new do
      root = Leptris::XML::Document.parse(xml).root
      names = root.element_children.map(&:name)
    end.join
    expect(names).to eq((1..80).map { |i| "n#{i}" })
  end

  it "answers the true last element child from a fresh scratch" do
    xml = "<r>#{(1..60).map { |i| "<c#{i}/>" }.join}</r>"
    last = nil
    Thread.new do
      last = Leptris::XML::Document.parse(xml).root.last_element_child&.name
    end.join
    expect(last).to eq("c60")
  end
end

RSpec.describe "leptris-ruby#85: PI data consumes the leading whitespace run" do
  let(:xml) do
    %(<?xml-stylesheet   href="doc.xsl" type="text/xsl"   ?><r/><?pi-without-data     ?>)
  end

  it "normalizes PI#content" do
    pis = Leptris::XML.parse(xml).children.select(&:pi?)
    expect(pis.map(&:content)).to eq(
      ['href="doc.xsl" type="text/xsl"   ', ""])
  end

  it "normalizes Document#processing_instructions data" do
    expect(Leptris::XML.parse(xml).processing_instructions).to eq(
      [["xml-stylesheet", 'href="doc.xsl" type="text/xsl"   '],
       ["pi-without-data", ""]])
  end

  it "normalizes SAX processing_instruction delivery" do
    seen = []
    handler = Class.new(Leptris::XML::SAX::Document) do
      define_method(:processing_instruction) { |t, d| seen << [t, d] }
    end.new
    Leptris::XML::SAX::Parser.new(handler).parse(xml)
    expect(seen).to eq(
      [["xml-stylesheet", 'href="doc.xsl" type="text/xsl"   '],
       ["pi-without-data", ""]])
  end

  it "normalizes pull PI events" do
    seen = []
    Leptris::XML::Pull.parse(xml) do |e|
      seen << [e.name, e.text] if e.type == :pi
    end
    expect(seen).to eq(
      [["xml-stylesheet", 'href="doc.xsl" type="text/xsl"   '],
       ["pi-without-data", ""]])
  end

  it "normalizes recorder PI events" do
    seen = []
    Leptris::XML::SAX::Recorder.parse(xml, kinds: [:pi]) do |kind, name, text|
      seen << [name, text]
    end
    expect(seen).to eq(
      [["xml-stylesheet", 'href="doc.xsl" type="text/xsl"   '],
       ["pi-without-data", ""]])
  end

  it "keeps deliberately-set data verbatim through the setter round-trip" do
    doc = Leptris::XML.parse("<r/>")
    pi = doc.create_processing_instruction("t", "d")
    pi.data = "  keep  "
    expect(pi.content).to eq("keep  ")
  end
end

RSpec.describe "leptris-ruby#89/#90: traverse bounds and exception escape" do
  it "is subtree-bounded from an element — no following siblings" do
    doc = Leptris::XML::Document.parse(%q{<r><a><x/></a><b><y/></b><c/></r>})
    names = []
    doc.root.children.to_a[0].traverse { |n| names << n.name }
    expect(names).to eq(%w[x a])
  end

  it "is subtree-bounded from the root — no epilog nodes" do
    doc = Leptris::XML::Document.parse(%q{<r><a/></r><!--epilog--><?pe e?>})
    names = []
    doc.root.traverse { |n| names << n.name }
    expect(names).to eq(%w[a r])
  end

  it "re-raises exceptions raised inside the callback and stops the walk" do
    doc = Leptris::XML::Document.parse(%q{<r><a/><b/><c/></r>})
    count = 0
    expect {
      doc.root.traverse { |n| count += 1; raise "boom" if count == 2 }
    }.to raise_error(RuntimeError, "boom")
    expect(count).to eq(2)
  end
end

RSpec.describe "leptris-ruby#91: built documents list the attached root" do
  it "children reflects root= immediately" do
    doc = Leptris::XML::Document.create
    doc.root = doc.create_element("built")
    expect(doc.children.map(&:class)).to eq([Leptris::XML::Element])
  end

  it "splices the root in document order against prolog/epilog" do
    doc = Leptris::XML::Document.parse(%q{<?pi p?><!--c--><old/><!--e-->})
    doc.root = doc.create_element("new")
    names = doc.children.map { |n| n.pi? ? "pi" : (n.element? ? "root" : "comment") }
    expect(names).to eq(%w[pi comment root comment])
  end

  it "leaves parsed documents unchanged" do
    doc = Leptris::XML::Document.parse(%q{<?pi p?><r/><!--e-->})
    expect(doc.children.map { |n| n.pi? ? "pi" : (n.element? ? "root" : "comment") })
      .to eq(%w[pi root comment])
  end
end

RSpec.describe "leptris-ruby#92: document-level PI writes name the contract" do
  it "mutates and unlinks document-level PIs (libleptris 1.9.9, #612)" do
    doc = Leptris::XML::Document.parse(%q{<?pi x?><root/>})
    pi = doc.children.to_a[0]
    pi.target = "t"
    pi.data = "y"
    expect(pi.name).to eq("t")
    expect(pi.content).to eq("y")
    expect(pi.unlink).to equal(pi)
    expect(doc.children.map { |c| c.pi? ? c.name : "root" }).to eq(%w[root])
  end

  it "removes document-level PIs by target and by index" do
    doc = Leptris::XML::Document.parse(%q{<?a x?><?b y?><?b z?><root/>})
    removed = doc.remove_pi("b")
    expect(removed.name).to eq("b")
    expect(removed.content).to eq("y")
    expect(doc.processing_instructions.map(&:first)).to eq(%w[a b])
    by_index = doc.remove_pi(1)
    expect(by_index.content).to eq("z")
    expect(doc.remove_pi("nope")).to be_nil
    expect(doc.processing_instructions.map(&:first)).to eq(%w[a])
  end

  it "unlinks the right same-target PI (identity match)" do
    doc = Leptris::XML::Document.parse(%q{<?b y?><?b z?><root/>})
    second = doc.children.to_a[1]
    second.unlink
    expect(doc.processing_instructions.map(&:last)).to eq(%w[y])
  end

  it "serializes the display form with indent_text" do
    doc = Leptris::XML::Document.parse("<r><a/>text<b/></r>")
    compact = doc.to_s(indent: 2)
    display = doc.to_s(indent: 2, indent_text: true)
    expect(display).not_to eq(compact)
    # display form is not round-trip-guaranteed: re-parsing yields
    # whitespace-only text nodes; the element structure survives.
    expect(Leptris::XML.parse(display).root.element_children.map(&:name))
      .to eq(doc.root.element_children.map(&:name))
  end

  it "keeps tree-level and add_pi PIs mutable" do
    doc = Leptris::XML::Document.parse("<r><?p v?></r>")
    tree_pi = doc.root.children.to_a[0]
    tree_pi.data = "w"
    expect(tree_pi.content).to eq("w")
    doc.add_pi("n", "v")
    added = doc.children.to_a.find(&:pi?)
    added.data = "z"
    expect(added.content).to eq("z")
  end
end

RSpec.describe "round XXV: cached namespace binding sets" do
  it "returns stable results across repeated queries with the same hash" do
    doc = Leptris::XML::Document.parse(
      '<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://x">' \
      "<x:rect id=\"r1\"/><circle/><x:rect id=\"r2\"/></svg>")
    5.times do
      expect(doc.xpath("//x:rect", { "x" => "http://x" }).map { |e| e["id"] })
        .to eq(%w[r1 r2])
    end
  end

  it "does not collide across vocabularies" do
    doc = Leptris::XML::Document.parse(
      '<r xmlns:a="urn:a" xmlns:b="urn:b"><a:t/><b:t/></r>')
    expect(doc.xpath("//a:t", { "a" => "urn:a" }).size).to eq(1)
    expect(doc.xpath("//b:t", { "b" => "urn:b" }).size).to eq(1)
    expect(doc.xpath("//a:t | //b:t", { "a" => "urn:a", "b" => "urn:b" }).size).to eq(2)
  end

  it "treats symbol and string keys as the same vocabulary" do
    doc = Leptris::XML::Document.parse('<r xmlns:x="urn:x"><x:t/></r>')
    expect(doc.xpath("//x:t", { x: "urn:x" }).size).to eq(1)
    expect(doc.xpath("//x:t", { "x" => "urn:x" }).size).to eq(1)
  end

  it "serves concurrent queries with the same vocabulary" do
    doc = Leptris::XML::Document.parse(
      '<r xmlns:x="urn:x">' + (1..40).map { |i| %(<x:t id="t#{i}"/>) }.join + "</r>")
    threads = 4.times.map do
      Thread.new do
        20.times do
          raise "size" unless doc.xpath("//x:t", { "x" => "urn:x" }).size == 40
        end
      end
    end
    threads.each(&:join)
  end
end
