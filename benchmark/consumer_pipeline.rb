# frozen_string_literal: true

# Consumer-pipeline benchmark leg (leptris-ruby#178 ask 3):
# a nested document walked into TYPED Ruby objects — the shape
# model frameworks (lutaml-model etc.) pay per parse. Engine-level
# benchmarks hide this overhead; Amdahl makes it the dominant term.
#
# Modes:
#   bundle exec ruby -Ilib benchmark/consumer_pipeline.rb            # warm, best-of-5 + alloc deltas
#   bundle exec ruby -Ilib benchmark/consumer_pipeline.rb --one-shot # single run, fresh process (CLI shape)
#
# The one-shot driver (below) spawns N fresh ruby processes and
# reports the MEDIAN — YJIT warmup never amortizes in one-shot
# workloads, which is where native engines structurally win.

Item = Struct.new(:id, :sku, :category, :name, :desc, :price, :stock, keyword_init: true)
Catalog = Struct.new(:version, :items, keyword_init: true)

def build_xml(n = 7000)
  %(<catalog version="2.0">) +
    (1..n).map do |i|
      %(<item id="#{i}" sku="SKU-#{i}" category="#{i % 20}">) +
        %(<name>Item #{i} premium</name>) +
        %(<desc>Some description text #{i} with words</desc>) +
        %(<price currency="USD">#{i}.99</price>) +
        %(<stock warehouse="w#{i % 7}">#{i % 100}</stock>) +
        %(</item>)
    end.join + %(</catalog>)
end

def pipeline(xml, xml_module)
  doc = xml_module::Document.parse(xml)
  Catalog.new(
    version: doc.root["version"],
    items: doc.root.element_children.map do |item|
      Item.new(
        id: item["id"], sku: item["sku"], category: item["category"],
        name: item.at("name").content,
        desc: item.at("desc").content,
        price: item.at("price").content,
        stock: item.at("stock").content)
    end)
end

require "leptris/xml"

if ARGV.delete("--one-shot")
  # Fresh-process single run: wall time for parse + typed walk.
  xml = build_xml
  GC.start
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  catalog = pipeline(xml, Leptris::XML)
  secs = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  puts format("%.1f", secs * 1000)
  raise "pipeline sanity" unless catalog.items.size == 7000
  exit
end

xml = build_xml

# allocation deltas for ONE pipeline run (load-independent)
gc_before = GC.stat(:total_allocated_objects)
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
pipeline(xml, Leptris::XML)
one_secs = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
allocs = GC.stat(:total_allocated_objects) - gc_before
puts format("one pipeline run: %8.1f ms   %d allocations (incl. %d item structs)",
            one_secs * 1000, allocs, 7000)

5.times do
  GC.start
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pipeline(xml, Leptris::XML)
  puts format("warm:               %8.1f ms", (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1000)
end

# one-shot medians over fresh processes — the CLI workload shape
require "open3"
medians = {}
{ leptris: "Leptris" }.each do |name, _|
  runs = 9.times.map do
    out, _err, _st = Open3.capture3(RbConfig.ruby, "-Ilib",
      __FILE__, "--one-shot")
    out.to_f
  end
  medians[name] = runs.sort[runs.size / 2]
end
puts format("one-shot MEDIAN (fresh process, n=9): %.1f ms", medians[:leptris])
