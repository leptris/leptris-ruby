# frozen_string_literal: true

require "spec_helper"

# The builder face (leptris-ruby#374 lever 2): markup-accumulating
# subtree construction with ONE fragment-parse crossing at flush.
RSpec.describe "Builder / build (#374)" do
  it "builds a fresh document subtree in one crossing" do
    doc = Leptris::XML::Document.create
    doc.build do |b|
      b.catalog(id: "c", rev: 2) do
        (1..3).each do |i|
          b.item(id: i) do
            b.name "Item #{i}"
            b.price "#{i}.99"
          end
        end
      end
    end
    expect(doc.root.name).to eq("catalog")
    expect(doc.xpath("//item").size).to eq(3)
    expect(doc.xpath("//item[@id='2']/price").first.content).to eq("2.99")
  end

  it "escapes text and attribute values" do
    doc = Leptris::XML::Document.create
    doc.build do |b|
      b.r do
        b.note "a & b < c > d"
        b.tagged value: "quote \" and & and <"
      end
    end
    expect(doc.root.to_xml)
      .to include("a &amp; b &lt; c &gt; d")
      .and include(%(value="quote &quot; and &amp; and &lt;"))
    expect(doc.xpath("//note").first.content).to eq("a & b < c > d")
    expect(doc.xpath("//tagged").first["value"]).to eq("quote \" and & and <")
  end

  it "supports text/cdata/comment and raw splices" do
    doc = Leptris::XML::Document.create
    doc.build do |b|
      b.r do
        b.text "plain"
        b.cdata "raw < stuff"
        b.comment "noted"
        b.raw("<fixed attr='1'/>")
      end
    end
    expect(doc.xpath("//fixed").first["attr"]).to eq("1")
    expect(doc.xpath("//r").first.children.map(&:node_type))
      .to include(1, 3, 2, 0)  # TEXT, CDATA, COMMENT, ELEMENT
  end

  it "appends into an existing root with Element#build" do
    doc = Leptris::XML::Document.parse(%(<catalog><legacy/></catalog>))
    doc.root.build do |b|
      b.item(id: "new") { b.name "N" }
    end
    expect(doc.root.element_children.map(&:name)).to eq(%w[legacy item])
  end

  it "rejects malformed names and multi-root buffers" do
    doc = Leptris::XML::Document.create
    expect { doc.build { |b| b.element("bad name") } }
      .to raise_error(ArgumentError, /names must match/)
    expect { doc.build { |b| b.a; b.b } }
      .to raise_error(Leptris::XML::Error, /exactly one root/)
  end

  it "numeric values stringify without quoting surprises" do
    doc = Leptris::XML::Document.create
    doc.build do |b|
      b.r { b.v 42 }
    end
    expect(doc.xpath("//v").first.content).to eq("42")
  end
end
