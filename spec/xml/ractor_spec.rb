# frozen_string_literal: true

require "spec_helper"

# Ractor (actor-model) support: each ractor owns its documents
# end-to-end — parse, XPath, XSLT, descriptor materialization — with
# no shared mutable state crossing ractor boundaries. The engine's
# global structures (root-doc map, arena retain pool) are
# mutex-synchronized; the native ext declares ractor safety and its
# class caches are GC-marked immortals.
# ffi's aarch64-mingw-ucrt attach path wraps every attached
# function in an un-shareable Proc (libffi #905 workaround); its
# Library#freeze redemption (engaged from ffi.rb on that platform)
# needs Ractor.shareable_proc, which Ruby < 3.5 lacks. Attached
# calls from child ractors are therefore impossible there — skip
# until the runtime catches up; every other platform runs these.
RSpec.describe "Ractor support",
  if: defined?(Ractor) &&
      !(RUBY_PLATFORM == "aarch64-mingw-ucrt" &&
        !defined?(Ractor.shareable_proc)) do
  # Resolve the autoload tree in the MAIN ractor first: a child
  # ractor's autoload request is serviced by main, and a main
  # blocked in Ractor#take is not schedulable — under load that
  # pairing wedges (CRuby ractor-barrier race). One parse pulls
  # Document/Element/Node/Searchable/XPath in.
  before(:all) { Leptris::XML.parse("<warm/>") }

  def take(r)
    r.respond_to?(:value) ? r.value : r.take
  end

  let(:xml) do
    %(<catalog version="2.0">) +
      (1..50).map { |i|
        %(<item id="#{i}"><name>Item #{i}</name><price>#{i}.99</price></item>)
      }.join + %(</catalog>)
  end

  def parse_and_sum(src)
    Ractor.new(src) do |s|
      doc = Leptris::XML.parse(s)
      total = 0
      doc.root.element_children.each do |item|
        total += item["id"].to_i
        total += item.element_children.first.content.bytesize
      end
      [total, doc.root["version"]]
    end
  end

  it "parses and reads in parallel ractors with correct results" do
    results = 4.times.map { parse_and_sum(xml) }.map { |r| take(r) }
    expect(results).to all(be_an(Array))
    expect(results.map(&:first).uniq).to eq([results.first.first])
    expect(results.first.first).to eq((1..50).sum { |i| i + "Item #{i}".bytesize })
    expect(results.map(&:last).uniq).to eq(["2.0"])
  end

  it "isolates mutations across ractors" do
    racts = 4.times.map do |i|
      Ractor.new(xml, i) do |s, n|
        doc = Leptris::XML.parse(s)
        doc.root["mutated"] = n.to_s
        doc.root["mutated"]
      end
    end
    expect(racts.map { |r| take(r) }.uniq.length).to eq(4)
  end

  it "runs XPath in ractors" do
    r = Ractor.new(xml) do |s|
      doc = Leptris::XML.parse(s)
      doc.xpath("//item[price > 25]/@id").map(&:to_s).sort
    end
    expect(take(r)).to eq((25..50).map(&:to_s))
  end

  it "frees documents through GC inside a ractor" do
    r = Ractor.new do
      50.times do
        doc = Leptris::XML.parse("<r>#{'x' * 1000}</r>")
        raise "wrong name #{doc.root.name}" unless doc.root.name == "r"
      end
      GC.start
      :done
    end
    expect(take(r)).to be(:done)
    GC.start # finalizer drain on the main side too
  end
end
