# frozen_string_literal: true

# Ruby-level performance comparison: Taurus::XML (FFI → libtaurus v0.11.2)
# vs Nokogiri (C extension → libxml2).
#
# Run with: bundle exec ruby -Ilib benchmark/taurus_vs_nokogiri.rb
#
# Doc sizes capped at ~12 KB because `benchmark-ips` on 38 KB docs still
# crashes inside `taurus_node_freeze` (libtaurus #256, partially fixed
# in v0.11.2 — see benchmark/README.md). Plain `Benchmark` with explicit
# `Document#free` on 38 KB docs works fine.

require "benchmark"
require "taurus/xml"
require "nokogiri"

module Fixtures
  SMALL = "<catalog>" +
          (1..10).map { |i| "<book id='#{i}'><title>Book #{i}</title></book>" }.join +
          "</catalog>"

  MEDIUM = ("<catalog version='2.0'>" +
            (1..100).map do |i|
              "<book id='#{i}' lang='en'>" \
              "<title>Book #{i}</title>" \
              "<author id='a#{i}'>Author #{i}</author>" \
              "<price currency='USD'>#{i}.99</price>" \
              "</book>"
            end.join +
            "</catalog>").freeze
end

def time_it(label, n, &block)
  GC.start
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  n.times { yield }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  us_per_iter = (elapsed / n) * 1_000_000
  printf "  %-40s %8.2f µs/iter  (%d iters in %.3fs)\n", label, us_per_iter, n, elapsed
  us_per_iter
end

def ratio(label, taurus_us, nokogiri_us)
  r = nokogiri_us / taurus_us
  who = r > 1 ? "Taurus faster" : "Nokogiri faster"
  printf "  → %-30s Taurus/Nokogiri = %.2fx (%s)\n\n", label, r, who
end

N_PARSE_SMALL = 5_000
N_PARSE_MEDIUM = 1_000
N_QUERY = 10_000
N_TRAVERSE = 2_000
N_SERIALIZE = 1_000

puts "===== Parse — small (#{Fixtures::SMALL.bytesize} B) ====="
t = time_it("taurus parse small", N_PARSE_SMALL) { d = Taurus::XML::Document.parse(Fixtures::SMALL); d.free }
n = time_it("nokogiri parse small", N_PARSE_SMALL) { Nokogiri::XML(Fixtures::SMALL) }
ratio("parse small", t, n)

puts "===== Parse — medium (#{Fixtures::MEDIUM.bytesize} B) ====="
t = time_it("taurus parse medium", N_PARSE_MEDIUM) { d = Taurus::XML::Document.parse(Fixtures::MEDIUM); d.free }
n = time_it("nokogiri parse medium", N_PARSE_MEDIUM) { Nokogiri::XML(Fixtures::MEDIUM) }
ratio("parse medium", t, n)

# Pre-parse medium for query benchmarks
doc_t = Taurus::XML::Document.parse(Fixtures::MEDIUM)
doc_n = Nokogiri::XML(Fixtures::MEDIUM)

puts "===== XPath — count(//book) ====="
t = time_it("taurus xpath count()", N_QUERY) { doc_t.xpath("count(//book)") }
n = time_it("nokogiri xpath count()", N_QUERY) { doc_n.xpath("count(//book)") }
ratio("xpath count()", t, n)

puts "===== XPath — //book (nodeset of 100) ====="
t = time_it("taurus xpath //book", N_QUERY) { doc_t.xpath("//book") }
n = time_it("nokogiri xpath //book", N_QUERY) { doc_n.xpath("//book") }
ratio("xpath //book", t, n)

puts "===== XPath — predicate //book[@id='50'] ====="
t = time_it("taurus xpath predicate", N_QUERY) { doc_t.xpath("//book[@id='50']") }
n = time_it("nokogiri xpath predicate", N_QUERY) { doc_n.xpath("//book[@id='50']") }
ratio("xpath predicate", t, n)

puts "===== XPath — complex //book[price > 50] ====="
t = time_it("taurus xpath complex", N_QUERY) { doc_t.xpath("//book[price > 50]") }
n = time_it("nokogiri xpath complex", N_QUERY) { doc_n.xpath("//book[price > 50]") }
ratio("xpath complex", t, n)

puts "===== XPath — union //author | //title ====="
t = time_it("taurus xpath union", N_QUERY) { doc_t.xpath("//author | //title") }
n = time_it("nokogiri xpath union", N_QUERY) { doc_n.xpath("//author | //title") }
ratio("xpath union", t, n)

puts "===== Tree traversal (root.traverse) ====="
t = time_it("taurus traverse", N_TRAVERSE) { doc_t.root.traverse { |n| n.name } }
n = time_it("nokogiri traverse", N_TRAVERSE) { doc_n.root.traverse { |n| n.name } }
ratio("traverse", t, n)

puts "===== Serialize — Document#to_xml ====="
t = time_it("taurus serialize", N_SERIALIZE) { doc_t.to_xml }
n = time_it("nokogiri serialize", N_SERIALIZE) { doc_n.to_xml }
ratio("serialize", t, n)

doc_t.free

puts ""
puts "Note: benchmark-ips on 38 KB docs still crashes inside libtaurus"
puts "taurus_node_freeze (libtaurus #256, partially fixed in v0.11.2)."
puts "Plain Benchmark with explicit Document#free (used above) is fine."
puts "See benchmark/README.md for analysis."


