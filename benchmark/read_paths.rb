# frozen_string_literal: true

# Read-path benchmark harness — the loop shapes the architecture
# review rounds actually measure (rounds II-IV). Run before/after any
# read-path change:
#
#   bundle exec ruby benchmark/read_paths.rb
#
# Not part of CI (the benchmark group is excluded); numbers are
# machine-relative — compare runs on the same machine only.
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "leptris"
require "benchmark"

X = Leptris::XML
puts "leptris #{Leptris::VERSION} / ruby #{RUBY_VERSION}"

sax_xml = "<r>" + (1..200).map { |i| %(<item id="#{i}" class="c">v#{i}</item>) }.join + "</r>"
nodeset_xml = "<r>" + (1..500).map { |i| %(<a><n>#{i}</n></a>) }.join + "</r>"
xml = (1..300).map { |i|
  %(<item id="i#{i}" class="row" data-x="v#{i}"><name>Item #{i}</name><desc>café &amp; crème</desc></item>)
}.join
root = X::Document.parse(
  %(<catalog xmlns:c="urn:c" xmlns="urn:d">#{xml}</catalog>), readonly: true).root

class NullSaxHandler < X::SAX::Document; end

N = ENV.fetch("N", "400").to_i
Benchmark.bm(24) do |b|
  b.report("parse+query+serialize") do
    N.times do
      d = X::Document.parse(%(<r><a x="1">t</a><b/></r>))
      d.root.xpath("//a[@x='1']").first.name
      d.to_xml(no_decl: true)
      d.free
    end
  end
  b.report("attr reads (ro)") do
    N.times { root.element_children.each { |c| c["id"]; c["class"]; c.keys } }
  end
  b.report("namespaces loop (ro)") do
    N.times { root.element_children.each { |c| c.namespaces; c.namespace } }
  end
  b.report("content reads (ro)") do
    N.times { root.element_children.each { |c| c.element_children.each(&:content) } }
  end
  b.report("css loop") do
    N.times { root.css("item").length; root.css("item > name").length }
  end
  b.report("sax parse (200 items)") do
    parser = X::SAX::Parser.new(NullSaxHandler.new)
    N.times { parser.parse(sax_xml) }
  end
  b.report("nodeset xpath (500)") do
    N.times do
      doc = X::Document.parse(nodeset_xml)
      doc.root.xpath("//a").xpath("./n").length
      doc.free
    end
  end
end
