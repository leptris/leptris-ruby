# frozen_string_literal: true

# Post-publish smoke (the teptris-ruby gem-smoke template): the
# INSTALLED gem from rubygems — not the checkout — must parse,
# query, mutate, serialize, and validate, with the native layer
# when the platform ships it. Also guards the #318 class: the
# NODE_* constants must exist in the shipped layer (a packaging
# skew surfaces as a NameError on first use, not at require).
require "leptris"

abort "SMOKE FAIL: leptris did not define Leptris::VERSION" unless defined?(Leptris::VERSION)
puts "leptris #{Leptris::VERSION} on #{RUBY_PLATFORM} (ruby #{RUBY_VERSION})"

doc = Leptris::XML.parse("<r id='1'><a x='2'>t1</a><a>t2</a></r>")
raise "parse: root" unless doc.root.name == "r"
raise "xpath: children" unless doc.root.xpath("a").size == 2
raise "attr read" unless doc.at_xpath("a")["x"] == "2"

doc.at_xpath("a").content = "z"
raise "mutate" unless doc.at_xpath("a").content == "z"
raise "serialize" unless doc.to_xml.include?('<a x="2">z</a>')

rng = Leptris::XML::RelaxNG.parse(
  '<element name="r" xmlns="http://relaxng.org/ns/structure/1.0">' \
  "<attribute name=\"id\"/></element>")
rng_doc = Leptris::XML::Document.parse(%q{<r id='1'/>})
raise "rng verdict" unless rng.valid?(rng_doc)
raise "rng errors shape" unless rng.validate_errors(rng_doc).is_a?(Array)
raise "rng report shape" unless rng.validate_report(rng_doc).is_a?(Array)

# The #318 class: node-kind constants must live in the shipped
# Ruby layer (plain constants cannot go missing with the lib).
raise "NODE constants" unless Leptris::XML::FFI::NODE_ELEMENT

layer = defined?(Leptris::XML::NATIVE_FAST) ? "native" : "ffi"
puts "SMOKE OK (#{layer} layer)"
