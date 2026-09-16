# frozen_string_literal: true

# The #1094 node-surface parity wave (libleptris 1.9.176,
# leptris-ruby#212): entity references, the XML declaration,
# programmatic DOCTYPE, and document-PI identity/removal — the
# surfaces that let downstream wrappers delete their value-object
# emulation layers.
RSpec.describe "node-surface parity (1.9.177, #212)" do
  it "keeps &name; references unexpanded with the parse flag" do
    doc = Leptris::XML::Document.parse(
      %q{<r>a &foo; b &#65;</r>},
      options: Leptris::XML::ParseOptions.keep_entity_refs)
    kids = doc.root.children
    expect(kids.map(&:class)).to eq(
      [Leptris::XML::Text, Leptris::XML::EntityReference,
       Leptris::XML::Text])
    expect(kids[1].name).to eq("foo")
    # character references still expand; entity refs serialize back
    expect(doc.to_xml).to include("a &foo; b A")
  end

  it "creates entity references that serialize verbatim" do
    doc = Leptris::XML::Document.create
    doc.root = doc.create_element("r")
    doc.root.add_child(doc.create_text_node("x"))
    doc.root.add_child(doc.create_entity_reference("bar"))
    expect(doc.to_xml).to include("<r>x&bar;</r>")
  end

  it "reads and writes the XML declaration" do
    doc = Leptris::XML::Document.create
    expect(doc.xml_version).to be_nil.or eq("1.0")
    doc.xml_version = "1.1"
    doc.xml_encoding = "UTF-8"
    doc.xml_standalone = true
    doc.root = doc.create_element("r")
    expect(doc.xml_version).to eq("1.1")
    expect(doc.xml_standalone).to be(true)
    expect(doc.to_xml)
      .to start_with(%q{<?xml version="1.1" encoding="UTF-8" standalone="yes"?>})
  end

  it "creates a DOCTYPE with PUBLIC/SYSTEM ids in document position" do
    doc = Leptris::XML::Document.create
    dt = doc.set_doctype("root", public_id: "-//X//DTD Y//EN",
                                 system_id: "y.dtd")
    doc.root = doc.create_element("root")
    expect(dt.name).to eq("root")
    expect(doc.to_xml)
      .to include(%q{<!DOCTYPE root PUBLIC "-//X//DTD Y//EN" "y.dtd">})
  end

  it "gives document PIs identity, epilog anchoring, and removal" do
    doc = Leptris::XML::Document.parse(%q{<r/>})
    pi = doc.add_pi("xml-stylesheet", %q{type="text/xsl" href="s.xsl"})
    expect(pi).to be_a(Leptris::XML::ProcessingInstruction)
    expect(pi.content).to eq(%q{type="text/xsl" href="s.xsl"})
    expect(doc.processing_instructions.size).to eq(1)
    expect(pi.equal?(doc.processing_instructions.first)).to be(false) # pairs list
    doc.remove_child(pi)
    expect(doc.processing_instructions).to be_empty
    expect(doc.to_xml).not_to include("xml-stylesheet")
  end

  it "C14N omits redundant namespace redeclarations (upstream #1096)" do
    xml = %q{<doc xmlns="urn:d"><e xmlns="urn:d">x</e></doc>}
    doc = Leptris::XML::Document.parse(xml)
    expect(doc.canonicalize)
      .to eq(%q{<doc xmlns="urn:d"><e>x</e></doc>})
  end
end
