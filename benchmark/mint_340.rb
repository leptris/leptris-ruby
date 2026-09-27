# frozen_string_literal: true

# #340 acceptance decomposition — the same shapes the issue
# measured (CLOCK_PROCESS_CPUTIME_ID medians; 100-node builds,
# 2,251-node catalog walks) plus the registered-klass rows the new
# machinery enables. Run:
#   bundle exec ruby benchmark/mint_340.rb

require "leptris/xml"
require "leptris/xml/native_layer"
require "nokogiri"

class BuildEl < Leptris::XML::NativeNode; end
class WalkEl < Leptris::XML::NativeNode; end
class WalkTx < Leptris::XML::NativeNode; end

CATALOG = ("<catalog>" +
           (1..750).map { |i|
             "<item id='#{i}' sku='S#{i}'><title>Item #{i}</title>" \
             "<desc>Some description text #{i} with words</desc></item>"
           }.join + "</catalog>").freeze

def cpu_median(n)
  samples = []
  n.times do
    t0 = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    yield
    samples << Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - t0
  end
  samples.sort![samples.size / 2]
end

N_BUILD = 100

puts format("%-52s %10s", "row (build, per node)", "µs")
rows = {}

rows["raw create_element_with_attrs (address back)"] =
  cpu_median(60) do
    doc = Leptris::XML::Document.parse("<r/>")
    root_addr = doc.root.c_ptr.address
    doc_addr = doc.c_ptr.address
    N_BUILD.times do |i|
      Leptris::XML::Native.create_element_with_attrs(
        doc_addr, root_addr, "e", ["id", i.to_s, "k", "v"])
    end
    doc.free
  end / N_BUILD * 1e6

rows["wrapped create (binding mint, no registration)"] =
  cpu_median(60) do
    doc = Leptris::XML::Document.parse("<r/>")
    root_addr = doc.root.c_ptr.address
    N_BUILD.times do |i|
      Leptris::XML::Native.create_element_with_attrs_wrapped(
        doc, root_addr, "e", ["id", i.to_s, "k", "v"])
    end
    doc.free
  end / N_BUILD * 1e6

rows["wrapped create (registered consumer klass)"] =
  cpu_median(60) do
    doc = Leptris::XML::Document.parse("<r/>")
    doc.register_wrapper_klasses([BuildEl, nil, nil, nil, nil])
    root_addr = doc.root.c_ptr.address
    N_BUILD.times do |i|
      Leptris::XML::Native.create_element_with_attrs_wrapped(
        doc, root_addr, "e", ["id", i.to_s, "k", "v"])
    end
    doc.free
  end / N_BUILD * 1e6

rows["nokogiri Node.new + attr + add_child"] =
  cpu_median(60) do
    doc = Nokogiri::XML("<r/>")
    root = doc.root
    N_BUILD.times do |i|
      e = Nokogiri::XML::Node.new("e", doc)
      e["id"] = i.to_s
      e["k"] = "v"
      root.add_child(e)
    end
  end / N_BUILD * 1e6

rows.each { |k, v| puts format("%-52s %10.2f", k, v) }

puts ""
puts format("%-52s %10s", "row (cold walk+read, per node)", "ns")
wrows = {}
node_count = 750 * 3 + 1

wrows["binding visit + content (no registration)"] =
  cpu_median(30) do
    doc = Leptris::XML::Document.parse(CATALOG)
    n = 0
    doc.root.visit { |node, _| n += node.content.bytesize rescue 0 }
    doc.free
    n
  end / node_count * 1e9

wrows["visit + content (registered consumer klasses)"] =
  cpu_median(30) do
    doc = Leptris::XML::Document.parse(CATALOG)
    doc.register_wrapper_klasses([WalkEl, WalkTx, nil, nil, nil])
    n = 0
    doc.root.visit { |node, _| n += node.content.bytesize rescue 0 }
    doc.free
    n
  end / node_count * 1e9

wrows["nokogiri traverse + text"] =
  cpu_median(30) do
    doc = Nokogiri::XML(CATALOG)
    n = 0
    doc.root.traverse { |node| n += (node.text.bytesize rescue 0) }
    n
  end / node_count * 1e9

wrows.each { |k, v| puts format("%-52s %10.0f", k, v) }
