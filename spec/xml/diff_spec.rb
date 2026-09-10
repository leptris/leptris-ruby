# frozen_string_literal: true

RSpec.describe Leptris::XML::Diff do
  def doc(xml)
    Leptris::XML::Document.parse(xml)
  end

  it "reports zero ops for identical trees" do
    a = doc("<r><i id='1'>old</i><i id='2'>x</i></r>")
    b = doc("<r><i id='1'>old</i><i id='2'>x</i></r>")
    expect(described_class.identical?(a, b)).to be true
    expect(described_class.diff(a, b).ops).to eq(0)
  end

  it "surfaces attribute, text, insert and delete ops" do
    a = doc("<r><i id='1'>old</i><tail/></r>")
    b = doc("<r><i id='2'>new</i><extra/></r>")
    script = described_class.diff(a, b)
    expect(script.ops).to eq(4)
    ops = script.each_op.to_a
    attr = ops.find { |o| o.type == :update_attr }
    expect(attr.path).to eq("/r/i")
    expect(attr.name).to eq("id")
    expect(attr.before).to eq("1")
    expect(attr.after).to eq("2")
    text = ops.find { |o| o.type == :update_text }
    expect(text.before).to eq("old")
    expect(text.after).to eq("new")
    ins = ops.find { |o| o.type == :insert }
    expect(ins.name).to eq("extra")
    dele = ops.find { |o| o.type == :delete }
    expect(dele.name).to eq("tail")
    expect(dele.path).to eq("/r/tail[1]")
  end

  it "serializes to the line-per-op form" do
    a = doc("<r><i>old</i></r>")
    b = doc("<r><i>new</i></r>")
    out = described_class.diff(a, b).serialize
    expect(out).to include('~ /r/i "old" -> "new"')
  end

  it "ignores whitespace-only text nodes on request" do
    a = doc("<r><i>x</i></r>")
    b = doc("<r>\n  <i>x</i>\n</r>")
    expect(described_class.identical?(a, b)).to be false
    expect(
      described_class.identical?(a, b, ignore_ws: true)
    ).to be true
  end
end
