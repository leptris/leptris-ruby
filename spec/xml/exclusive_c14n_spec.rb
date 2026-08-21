# frozen_string_literal: true

require "leptris/xml"

# Real W3C Exclusive XML Canonicalization 1.0 (https://www.w3.org/2001/10/xml-exc-c14n#)
# coverage. v0.5.3 shipped the real algorithm; v0.5.2 was a stub routed to
# canonical. These specs assert the algorithm's distinguishing behaviors:
#
# 1. Visibly-used namespace prefixes are emitted on the element that uses them.
# 2. Unused inherited namespace prefixes are dropped (vs canonical, which keeps
#    them in scope).
# 3. Caller-supplied inclusive namespace prefixes are force-included.
# 4. Output differs from canonical mode for the same input on namespace-heavy XML.

RSpec.describe "Exclusive C14N (v0.5.3 #183 real implementation)" do
  # Classic W3C exc-c14n example: ancestor <a> declares two prefixes,
  # <b> uses n1, <c> uses n2. Exclusive should emit each declaration on the
  # element that uses it, not duplicate either on the other.
  let(:xml) do
    <<~XML
      <a xmlns:n1="http://n1.example" xmlns:n2="http://n2.example">
        <b n1:attr="1">
          <c n2:attr="2"/>
        </b>
      </a>
    XML
  end
  let(:doc) { Leptris::XML::Document.parse(xml) }
  let(:b)   { doc.root.first_element_child }

  describe "visibly-used prefix emission" do
    it "emits xmlns:n1 on <b> because n1 is visibly used there" do
      exclusive = b.canonicalize(exclusive: true)
      expect(exclusive)
        .to match(%r{<b\s+xmlns:n1="http://n1\.example"\s+n1:attr="1">})
    end

    it "emits xmlns:n2 on <c> because n2 is visibly used there" do
      exclusive = b.canonicalize(exclusive: true)
      expect(exclusive)
        .to match(%r{<c\s+xmlns:n2="http://n2\.example"\s+n2:attr="2">})
    end

    it "does NOT emit xmlns:n2 on <b> (visibly unused there)" do
      exclusive = b.canonicalize(exclusive: true)
      # The <b> open tag itself must not declare n2.
      b_open = exclusive[/<b[^>]*>/]
      expect(b_open).not_to include("xmlns:n2")
    end

    it "does NOT emit xmlns:n1 on <c> (visibly unused there)" do
      exclusive = b.canonicalize(exclusive: true)
      c_open = exclusive[/<c[^>]*>/]
      expect(c_open).not_to include("xmlns:n1")
    end
  end

  describe "canonical vs exclusive output differs" do
    it "produces different output for the same namespace-heavy input" do
      canonical = b.canonicalize(mode: Leptris::XML::FFI::C14N_MODE_CANONICAL)
      exclusive = b.canonicalize(mode: Leptris::XML::FFI::C14N_MODE_EXCLUSIVE)
      expect(canonical).not_to eq(exclusive)
    end

    it "matches via the exclusive: true shortcut" do
      explicit = b.canonicalize(mode: Leptris::XML::FFI::C14N_MODE_EXCLUSIVE)
      shortcut = b.canonicalize(exclusive: true)
      expect(shortcut).to eq(explicit)
    end
  end

  describe "inclusive namespace prefixes (caller force-include list)" do
    it "force-includes a prefix the subtree doesn't visibly use" do
      # <b> only visibly uses n1. Force-include n2 in the output of <b>
      # via the inclusive list — useful for enveloped-signature cases.
      out = b.canonicalize(Leptris::XML::FFI::C14N_1_0, %w[n2], exclusive: true)
      b_open = out[/<b[^>]*>/]
      expect(b_open).to include("xmlns:n1=")
      expect(b_open).to include("xmlns:n2=")
    end

    it "force-includes a prefix not declared anywhere in scope" do
      # 'undeclared' isn't in the document at all. libleptris should still
      # produce output (the prefix just won't resolve, but it shouldn't crash).
      out = b.canonicalize(Leptris::XML::FFI::C14N_1_0, %w[undeclared], exclusive: true)
      expect(out).to be_a(String)
      expect(out).to include("<b")
    end

    # Regression for upstream issue #194 (v0.5.4 and earlier): when a prefix
    # is BOTH visibly used by the element AND in the caller's inclusive list,
    # the output should declare that prefix exactly once. Prior to v0.5.5
    # libleptris emitted it twice, producing invalid XML.
    it "does not duplicate xmlns when a prefix is both visibly used and inclusive" do
      # n1 is visibly used by <b> (its attribute) AND we ask to force-include n1.
      out = b.canonicalize(Leptris::XML::FFI::C14N_1_0, %w[n1], exclusive: true)
      b_open = out[/<b[^>]*>/]
      expect(b_open.scan(/xmlns:n1=/).length).to eq(1),
        "expected exactly one xmlns:n1= on <b>, got: #{b_open}"
    end

    it "does not duplicate xmlns even when multiple prefixes overlap" do
      # n1 is visibly used on <b>, n2 is visibly used on <c>. Force-include both.
      # Per W3C exc-c14n §2.4, inclusive prefixes render on the apex element
      # of the canonicalized subtree, so both xmlns:n1 and xmlns:n2 land on <b>.
      # <c> then does NOT re-declare xmlns:n2 because the ancestor in the
      # output already has it.
      out = b.canonicalize(Leptris::XML::FFI::C14N_1_0, %w[n1 n2], exclusive: true)
      b_open = out[/<b[^>]*>/]
      c_open = out[/<c[^>]*>/]
      expect(b_open.scan(/xmlns:n1=/).length).to eq(1),
        "apex <b> should declare xmlns:n1 exactly once"
      expect(b_open.scan(/xmlns:n2=/).length).to eq(1),
        "apex <b> should declare xmlns:n2 once (force-included via inclusive list)"
      expect(c_open.scan(/xmlns:n2=/).length).to eq(0),
        "<c> must not re-declare xmlns:n2 (already rendered by output ancestor)"
      expect(c_open.scan(/xmlns:n1=/).length).to eq(0),
        "<c> must not declare xmlns:n1 (visibly unused there)"
    end
  end

  describe "subtree vs document scope" do
    it "Element#canonicalize operates on the element's subtree" do
      exclusive_subtree = b.canonicalize(exclusive: true)
      # Subtree output starts with <b>, not <a>
      expect(exclusive_subtree).to match(/\A\s*<b/)
    end

    it "Document#canonicalize operates on the whole document" do
      exclusive_doc = doc.canonicalize(exclusive: true)
      expect(exclusive_doc).to include("<a")
      expect(exclusive_doc).to include("<b")
      expect(exclusive_doc).to include("<c")
    end
  end

  describe "real-world enveloped signature scenario" do
    # In XMLDSIG, an enveloped signature signs everything except the
    # <ds:Signature> element. Exclusive C14N is used to canonicalize the
    # signed subtree. A prefix declared on the enveloping ancestor is only
    # emitted on the element that visibly uses it — never duplicated on
    # descendants that don't.
    it "emits a visibly-used declaration on the using element only" do
      xml = <<~XML
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <m:GetPrice xmlns:m="http://example.org/stock">
              <m:Symbol>IBM</m:Symbol>
            </m:GetPrice>
          </soap:Body>
        </soap:Envelope>
      XML
      doc = Leptris::XML::Document.parse(xml)
      body = doc.at_xpath("//soap:Body",
        { "soap" => "http://schemas.xmlsoap.org/soap/envelope/" })
      expect(body).not_to be_nil

      exclusive = body.canonicalize(exclusive: true)
      # soap:Body visibly uses soap (its own element name) → emit xmlns:soap on Body
      body_open = exclusive[/<soap:Body[^>]*>/]
      expect(body_open).to include("xmlns:soap=")
      # m:GetPrice visibly uses m → emit xmlns:m on GetPrice
      expect(exclusive).to include("<m:GetPrice")
      getprice_open = exclusive[/<m:GetPrice[^>]*>/]
      expect(getprice_open).to include("xmlns:m=")
      # m:Symbol doesn't re-emit xmlns:m (already declared by visible ancestor in output)
      symbol_open = exclusive[/<m:Symbol[^>]*>/]
      expect(symbol_open).not_to include("xmlns:m=")
    end
  end
end
