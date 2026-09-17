# frozen_string_literal: true

require "tmpdir"

# Libleptris 1.9.187-188 (the lockstep): the metanorma-driven RNG
# wave — foreign-namespace annotations, externalRef, anyName, and
# leptris_rng_parse_file error detail — plus the HTML after-body
# insertion-mode restore (#659).
RSpec.describe "libleptris 1.9.188 surfaces (lockstep)" do
  RNG_NS = "http://relaxng.org/ns/structure/1.0"

  it "skips foreign-namespace annotation elements in patterns (1.9.187)" do
    schema = <<~RNG
      <element name="r" xmlns="#{RNG_NS}" xmlns:a="http://relaxng.org/ns/compatibility/annotations/1.0">
        <a:documentation>Production annotation, not a pattern</a:documentation>
        <element name="c"><text/></element>
      </element>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)
    ok = Leptris::XML::Document.parse("<r><c>x</c></r>")
    expect(rng.valid?(ok)).to be true
  end

  it "splices externalRef grammars: start body + resolvable refs (1.9.188)" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "child.rng"), <<~RNG)
        <grammar xmlns="#{RNG_NS}">
          <start>
            <element name="e"><ref name="payload"/></element>
          </start>
          <define name="payload"><text/></define>
        </grammar>
      RNG
      host = File.join(dir, "host.rng")
      File.write(host, <<~RNG)
        <grammar xmlns="#{RNG_NS}">
          <start>
            <element name="r"><externalRef href="child.rng"/></element>
          </start>
        </grammar>
      RNG
      rng = Leptris::XML::RelaxNG::Schema.parse_file(host)
      expect(rng.valid?(Leptris::XML::Document.parse("<r><e>t</e></r>")))
        .to be true
      expect(rng.valid?(Leptris::XML::Document.parse("<r><x/></r>")))
        .to be false
    end
  end

  it "anyName matches any element name (RELAX NG 4.14, 1.9.188)" do
    schema = <<~RNG
      <element name="r" xmlns="#{RNG_NS}">
        <zeroOrMore><element><anyName/></element></zeroOrMore>
      </element>
    RNG
    rng = Leptris::XML::RelaxNG.parse(schema)
    expect(rng.valid?(Leptris::XML::Document.parse("<r/>"))).to be true
    expect(rng.valid?(Leptris::XML::Document.parse(%q{<r><a/><z/></r>})))
      .to be true
    # NOTE: bare text under the wildcard currently also validates —
    # engine-side laxness (leptris/leptris#1153), deliberately not
    # pinned here.
  end

  it "leptris_rng_parse_file publishes schema-parse detail (1.9.188)" do
    Dir.mktmpdir do |dir|
      broken = File.join(dir, "broken.rng")
      File.write(broken,
        "<grammar xmlns=\"#{RNG_NS}\"><start><notAPattern/></start></grammar>")
      expect do
        Leptris::XML::RelaxNG::Schema.parse_file(broken)
      end.to raise_error(Leptris::XML::Error) do |e|
        expect(e.message).to match(/schema parse failed: .+/)
        expect(e.message).to match(/pattern|element|unknown/i)
      end
    end
  end

  it "restores after-body mode on non-whitespace text (#659, 1.9.187)" do
    doc = Leptris::XML.parse_html(
      "<html><body><p>x</p></body>tail<!--c--></html>", mode: :whatwg)
    body = doc.at_css("body")
    expect(body.content).to include("tail")
    last = body.children.last
    expect(last.comment?).to be true
  end
end
