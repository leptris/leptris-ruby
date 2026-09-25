# frozen_string_literal: true

require "spec_helper"

# Bulk SAX records (leptris#1298, engine leptris_sax_records_parse
# 1.9.223+): one crossing drains the document into a flat record
# table; hosts materialize only what they consume. The Ruby walker
# mirrors the recorder's event semantics — elements in document
# order with parent/next-sib indices, text runs, and a flat attr
# table whose values carry the raw §3.3.3 whitespace flag. Outside
# the scannable subset the parse answers NOT_SUPPORTED and .open
# returns nil (callers fall back to the callback Recorder).
RSpec.describe Leptris::XML::SAX::Records do
  def drain(xml)
    described_class.open(xml)
  end

  it "drains elements, text, and attributes in document order" do
    table = drain("<r><item n=\"1\">t1</item><item n=\"2\">t2<b>k</b></item><last/></r>")
    expect(table).not_to be_nil
    expect(table.count).to eq(8)

    kinds = (0...table.count).map { |i| table.kind(i) }
    expect(kinds).to eq([0, 0, 1, 0, 1, 0, 1, 0])

    names = (0...table.count).map { |i| table.kind(i).zero? ? table.view(i) : nil }
    expect(names).to eq(["r", "item", nil, "item", nil, "b", nil, "last"])
    texts = (0...table.count).select { |i| table.kind(i) == 1 }.map { |i| table.view(i) }
    expect(texts).to eq(%w[t1 t2 k])

    expect(table.self_closing?(7)).to be(true)
    expect(table.self_closing?(1)).to be(false)

    pairs = []
    (0...table.count).each do |i|
      next if table.kind(i) != 0

      first = table.attr_first(i)
      (0...table.attr_count_of(i)).each do |k|
        pairs << [table.attr_name(first + k), table.attr_value(first + k)]
      end
    end
    expect(pairs).to eq([%w[n 1], %w[n 2]])
    table.free
  end

  it "flags raw attribute whitespace for consumer-side 3.3.3 normalization" do
    table = drain("<r a=\"x\r\ny\tz\">v</r>")
    expect(table.attr_value_has_ws?(0)).to be(true)
    expect(table.attr_value(0)).to eq("x\r\ny\tz")
    table.free
  end

  it "returns nil outside the scannable subset (comments)" do
    expect(drain("<r><!--c--></r>")).to be_nil
  end

  it "returns nil for malformed input (callback path reports position)" do
    expect(drain("<r><a></r>")).to be_nil
  end
end
