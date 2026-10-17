# frozen_string_literal: true

# leptris-ruby#486: an install that degrades to the FFI surface must
# produce BYTE-IDENTICAL parse/serialize output to the native read
# layer — a load failure is a performance degradation, never a
# semantics change (the #1738 class: undeclared-prefix handling
# differed between the lanes and flipped relaton's sanitizer output).
#
# The lane is chosen at require time, so each side runs in its own
# ruby and the spec diffs the two transcripts.
RSpec.describe "native vs FFI serialization parity (leptris-ruby#486)" do
  PROBE = <<~RUBY
    require "leptris"
    shapes = {
      undeclared_elem: "<root><jats:p>text</jats:p></root>",
      undeclared_attr: '<root x="1"><a jats:q="v">t</a></root>',
      declared_default: '<root xmlns="urn:d"><p>t</p></root>',
      prefixed_in_scope: '<root xmlns:jats="urn:j"><jats:p>t</jats:p></root>',
      xml_prefix: '<root><x xml:lang="en">t</x></root>',
      mixed: '<root xmlns:jats="urn:j">' \
             '<jats:p xml:id="i1">a<jats:italic>b</jats:italic></jats:p>' \
             '<other jats:k="v">c</other></root>',
    }
    shapes.each do |name, xml|
      puts "#{name}\\t\#{Leptris::XML::Document.parse(xml).root.to_xml}"
    end
  RUBY

  def lane_transcript(no_native)
    require "open3"
    ruby = File.join(RbConfig::CONFIG["bindir"],
                     RbConfig::CONFIG["ruby_install_name"])
    lib = File.expand_path("../lib", __dir__)
    env = { "LEPTRIS_LIB_PATH" => ENV["LEPTRIS_LIB_PATH"] }.compact
    env["LEPTRIS_NO_NATIVE"] = "1" if no_native
    out, err, status = Open3.capture3(env, ruby, "-I", lib, "-e", PROBE)
    expect(status).to be_success, "lane no_native=#{no_native}: #{err}"
    out
  end

  it "degraded installs serialize byte-identically" do
    native = lane_transcript(false)
    ffi = lane_transcript(true)
    expect(native.lines.size).to eq(6)
    expect(ffi).to eq(native)
  end
end
