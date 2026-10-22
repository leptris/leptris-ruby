# frozen_string_literal: true

begin
  require "leptris/xml/native_layer"
rescue LoadError
end

require "spec_helper"

# The iterate-every-result lane's residual (moxml row 0.5x of
# nokogiri): rows arrived unprimed, so the consumer's NodeSet loop
# paid a full wrap per row just to learn each row is its own
# wrapper. With optional (context, adapter), registered-klass rows
# are born primed and an all-native result extends with
# BulkIdentityRows — the certificate a consumer fast loop keys on.
# One object per native address stays the native-cache contract.
RSpec.describe "XPathResult.rows_bulk primed rows",
               if: defined?(Leptris::XML::NativeNode) &&
                   Leptris::XML::Native.respond_to?(:xpath_result_rows_bulk) do
  let(:el_klass) { Class.new(Leptris::XML::NativeNode) }
  let(:mx_context) { Object.new }
  let(:mx_adapter) { Object.new }

  let(:doc) do
    d = Leptris::XML::Document.parse(
      %(<r id="root"><a>one</a><a>two</a><!--note--></r>))
    d.register_wrapper_klasses([el_klass, nil, nil, nil, nil])
    d
  end

  def rows_for(expr, ctx = mx_context, adapter = mx_adapter)
    ptr = Leptris::XML::XPath.compile(expr)
            .eval_ptrs(doc.c_ptr, nil)
    doc.xpath_result_rows_bulk(ptr, ctx, adapter)
  end

  it "answers the mark for an all-native result" do
    expect(rows_for("//a")).to be_a(Leptris::XML::BulkIdentityRows)
  end

  it "births rows primed: @native is the node, context and adapter set" do
    rows_for("//a").each do |node|
      expect(node.instance_variable_get(:@native)).to equal(node)
      expect(node.instance_variable_get(:@context)).to be(mx_context)
      expect(node.instance_variable_get(:@adapter)).to be(mx_adapter)
    end
  end

  it "keeps the mark off synthetic attribute rows" do
    expect(rows_for("//@id"))
      .not_to be_a(Leptris::XML::BulkIdentityRows)
  end

  it "keeps the mark off scalar-sequence rows" do
    expect(rows_for("(1,2)"))
      .not_to be_a(Leptris::XML::BulkIdentityRows)
  end

  it "keeps unregistered documents unmarked" do
    plain = Leptris::XML::Document.parse(%(<r><a/><a/></r>))
    ptr = Leptris::XML::XPath.compile("//a").eval_ptrs(plain.c_ptr, nil)

    rows = plain.xpath_result_rows_bulk(ptr, mx_context, mx_adapter)
    expect(rows).not_to be_a(Leptris::XML::BulkIdentityRows)
  end

  it "answers a plain unmarked unprimed Array without a context (compat)" do
    ptr = Leptris::XML::XPath.compile("//a").eval_ptrs(doc.c_ptr, nil)
    rows = doc.xpath_result_rows_bulk(ptr)

    expect(rows).not_to be_a(Leptris::XML::BulkIdentityRows)
    expect(rows.first.instance_variable_defined?(:@context)).to be(false)
  end

  it "keeps identity: one address, one Ruby object across primed queries" do
    first = rows_for("//a")
    again = rows_for("//a")

    expect(again[0]).to equal(first[0])
    expect(again[1]).to equal(first[1])
  end

  it "keeps primed rows answering the walk-contract reads" do
    expect(rows_for("//a").map(&:name)).to eq(%w[a a])
    expect(rows_for("//a").map(&:content)).to eq(%w[one two])
  end
end
