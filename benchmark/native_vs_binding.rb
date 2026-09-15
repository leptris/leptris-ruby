# frozen_string_literal: true

# TODO.perf/06: the drift battery's walk/read rows through BOTH
# surfaces — the binding (FFI wrappers, memoized) and the native
# layer (TypedData, C-bound). Run:
#   bundle exec ruby -Ilib benchmark/native_vs_binding.rb
# Gate: interleaved best-of; skip interpretation under host load
# > 20 (see TODO.restructure/17's discipline).

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "leptris"

XML = %(<catalog version="2.0">) +
  (1..7000).map do |i|
    %(<item id="#{i}" sku="SKU-#{i}" category="#{i % 20}">) +
    %(<name>Item #{i} premium</name>) +
    %(<desc>Some description text #{i} with words</desc>) +
    %(<price currency="USD">#{i}.99</price>) +
    %(<stock warehouse="w#{i % 7}">#{i % 100}</stock>) +
    %(</item>)
  end.join + %(</catalog>)

def timed
  GC.start
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
end

def best_of(n = 5)
  n.times.map { timed { yield } }.min
end

load_avg = begin
  File.read("/proc/loadavg").to_f
rescue StandardError
  `uptime`.match(/([\d.]+) /)[1].to_f
end
if load_avg > 20
  puts "# SKIP: host load #{load_avg} > 20 (TODO.restructure/17 gate)"
  exit 0
end

doc = Leptris::XML::Document.parse(XML)
native = doc.native_node

rows = {
  "attr reads (binding)" => -> { doc.root.element_children.each { |it| it["sku"] } },
  "attr reads (native)" => -> { native.element_children.each { |it| it["sku"] } },
  "attr hash (native)" => -> { native.element_children.each(&:attributes) },
  "children walk (binding)" => -> { doc.root.children.each { |c| c } },
  "children walk (native)" => -> { native.children.each { |c| c } },
  "cold one-shot (binding)" => -> {
    d = Leptris::XML::Document.parse(XML)
    d.root.element_children.each { |it| it.name; it["id"]; it.content }
  },
  "cold one-shot (native)" => -> {
    d = Leptris::XML::Document.parse(XML)
    n = d.native_node
    n.element_children.each { |it| it.name; it["id"]; it.content }
  },
  "serialize (binding)" => -> { doc.to_xml },
  "serialize (native)" => -> { Leptris::XML::Native.fast_document_xml(doc.c_ptr.address, 0, true) },
}

puts format("%-26s %12s", "row", "best-of-5")
rows.each do |label, work|
  t = best_of { work.call }
  puts format("%-26s %10.2f ms", label, t * 1000)
end

# ---- moxml gap rows (TODO.perf/11, #204) --------------------------
# Per-operation binding floors on ONE node, interleaved best-of —
# the shapes of the 2x-Nokogiri mandate table. Budgets per the
# issue: [] <= 70ns, content <= 58ns (native faces, repeat reads);
# create+attach at parity with raw Nokogiri.
N = 200_000
one = doc.root.element_children.first
one_native = native.element_children.first
one["sku"]; one.content
one_native["sku"]; one_native.content

gap_rows = {
  "[] repeat (binding)" => -> { one["sku"] },
  "[] repeat (native)" => -> { one_native["sku"] },
  "content repeat (binding)" => -> { one.content },
  "content repeat (native)" => -> { one_native.content },
  "name repeat (binding)" => -> { one.name },
  "set_attribute (binding)" => -> { one["sku"] = "SKU-1" },
}

puts ""
puts format("%-26s %14s", "gap row", "best-of-5")
gap_rows.each do |label, work|
  t = best_of { N.times { work.call } }
  puts format("%-26s %11.0f ns", label, t / N * 1e9)
end

M = 20_000
def build_pair
  doc = Leptris::XML::Document.create
  root = doc.create_element("r")
  doc.root = root
  e = doc.create_element("field")
  e.add_child(doc.create_text_node("value"))
  root.add_child(e)
end

t = best_of { M.times { build_pair } }
puts format("%-26s %11.0f ns", "build create×2+attach", t / M * 1e9)
