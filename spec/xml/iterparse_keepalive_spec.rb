# frozen_string_literal: true

require "spec_helper"

# #279: leptris_iterparse_new_ex retains the input buffer and reads
# it lazily in bounded slices. Without a reference pinned on the
# iterator, the input String is collectable once .parse returns and
# the iterator walks freed memory — attribute reads intermittently
# came back nil (heap-layout dependent; CI rerun-green).
RSpec.describe Leptris::XML::Iterparse do
  let(:doc) do
    (+"").tap do |out|
      out << "<root>"
      1_000.times { |i| out << %(<user id="u#{i}"><name>Name #{i}</name></user>) }
      out << "</root>"
    end
  end

  it "keeps reading correct attributes after the input string is collectable" do
    it = described_class.parse(doc.dup)
    # let the input die, then reclaim its freed buffer with same-size
    # garbage — the lazy slices must NOT read the reclaimed bytes
    10.times { GC.start }
    junk = Array.new(8) { "Z" * doc.bytesize }
    first = nil
    seen = 0
    it.run do |element|
      seen += 1
      first ||= element["id"]
    end
    expect(seen).to eq(1_000)
    expect(first).to eq("u0")
    it.free
    junk.clear
  end

  it "reads correct attributes across every element under GC pressure" do
    it = described_class.parse(doc.dup)
    count = 0
    it.run do |element|
      expect(element["id"]).to eq("u#{count}")
      count += 1
    end
    expect(count).to eq(1_000)
    it.free
  end
end
