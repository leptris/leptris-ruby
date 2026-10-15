# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tmpdir"

# The 1.9.357 XInclude resolver-policy face (#1694): xml:base chain,
# XML Catalog mapping, and the no_network posture — routed through
# leptris_xinclude_process_opts. The attach also keeps audit:symbols
# in lockstep (the symbol ships in the vendored engine).
RSpec.describe "Document#process_xinclude (resolver policy)" do
  let(:doc) do
    Leptris::XML.parse(<<~XML)
      <r xmlns:xi="http://www.w3.org/2001/XInclude">
        <xi:include href="part.xml"/>
      </r>
    XML
  end

  it "is attached on the FFI layer" do
    expect(Leptris::XML::FFI).to respond_to(:leptris_xinclude_process_opts)
  end

  it "resolves relative hrefs against base_url" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "part.xml"), "<part/>")
      # RFC 3986 merge: a directory base ends with "/" (the C suite's
      # own convention) — "dir" + "part.xml" would merge wrong.
      doc.process_xinclude(base_url: "#{dir}/")
      expect(doc.root.children.find { |c| c.name == "part" }).not_to be_nil
    end
  end

  it "runs the no-network posture: a remote include is refused cleanly" do
    doc2 = Leptris::XML.parse(<<~XML)
      <r xmlns:xi="http://www.w3.org/2001/XInclude">
        <xi:include href="https://example.org/nope.xml"/>
      </r>
    XML
    expect { doc2.process_xinclude }.not_to raise_error
    expect(doc2.root.children.find { |c| c.name == "xi:include" }).to be_nil
  end
end
