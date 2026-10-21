# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# leptris-ruby#529: the moxml native XPath lane iterates a node-set
# result one crossing per row — every row crosses FFI into Ruby and
# mints a wrapper, so iterate-every-result measures 0.37x vs
# nokogiri while count-only is 1.49x. rows_bulk materializes the
# WHOLE result as registered NativeNodes in ONE C call: count,
# order, and identity preserved; synthetic attribute/sequence rows
# capture their values while the handle is alive; the handle frees
# in C (the eager caller owns nothing afterwards).
RSpec.describe "XPathResult.rows_bulk (leptris-ruby#529)",
               if: defined?(Leptris::XML::NativeNode) &&
                   Leptris::XML::Native.respond_to?(:xpath_result_rows_bulk) do
  let(:el_klass) { Class.new(Leptris::XML::NativeNode) }
  let(:tx_klass) { Class.new(Leptris::XML::NativeNode) }
  let(:cm_klass) { Class.new(Leptris::XML::NativeNode) }

  let(:doc) do
    d = Leptris::XML::Document.parse(
      %(<r id="root"><a>one</a><a>two</a><!--note--><b/>tail</r>))
    d.register_wrapper_klasses([el_klass, tx_klass, cm_klass, nil, nil])
    d
  end

  def rows_for(expr, document = doc)
    ptr = Leptris::XML::XPath.compile(expr)
            .eval_ptrs(document.c_ptr, nil)
    Leptris::XML::Native.xpath_result_rows_bulk(document, ptr.address)
  end

  it "returns every row as a registered NativeNode, in order" do
    rows = rows_for("//*")

    expect(rows).to be_an(Array)
    expect(rows.map { |n| [n.class, n.name] }).to eq([
      [el_klass, "r"], [el_klass, "a"],
      [el_klass, "a"], [el_klass, "b"]
    ])
  end

  it "mints each tree kind through the registered map" do
    expect(rows_for("//a")).to all(be_instance_of(el_klass))

    comments = rows_for("//comment()")
    expect(comments.map(&:class)).to eq([cm_klass])

    texts = rows_for("//text()")
    expect(texts.map(&:class)).to eq([tx_klass, tx_klass, tx_klass])
    expect(texts.map(&:content)).to eq(%w[one two tail])
  end

  it "keeps identity: one address, one Ruby object" do
    first = rows_for("//a")
    again = rows_for("//a")

    expect(again[0]).to equal(first[0])
    expect(again[1]).to equal(first[1])
  end

  it "shares identity with the walk-minted instances" do
    walked = []
    doc.root.visit { |n, _| walked << n }

    expect(rows_for("//r")[0]).to equal(walked[0])
  end

  it "captures attribute rows as ResultAttr" do
    rows = rows_for("//@id")

    expect(rows.map(&:class)).to eq([Leptris::XML::ResultAttr])
    expect(rows[0].name).to eq("id")
    expect(rows[0].value).to eq("root")
  end

  it "captures sequence rows as ResultText" do
    rows = rows_for("(1,2)")

    expect(rows.map(&:class))
      .to eq([Leptris::XML::ResultText, Leptris::XML::ResultText])
    expect(rows.map(&:content)).to eq(%w[1 2])
  end

  it "answers nil for non-nodeset results (scalar path stays with the caller)" do
    expect(rows_for("count(//a)")).to be_nil
  end

  it "keeps unregistered documents on the binding classes" do
    plain = Leptris::XML::Document.parse(%(<r><a/><a/><a/></r>))

    expect(rows_for("//a", plain))
      .to all(be_instance_of(Leptris::XML::Element))
  end

  it "passes through from the Document face" do
    ptr = Leptris::XML::XPath.compile("//a").eval_ptrs(doc.c_ptr, nil)

    expect(doc.xpath_result_rows_bulk(ptr).map(&:class))
      .to eq([el_klass, el_klass])
  end
end
