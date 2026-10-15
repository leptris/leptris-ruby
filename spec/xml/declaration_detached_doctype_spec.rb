# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#459 — node faces for the document declaration and
# detached DOCTYPE creation (retires moxml's CustomizedLeptris).
RSpec.describe "Declaration node face + detached DOCTYPE (ruby#459)" do
  describe "Declaration as a node (ask 1)" do
    let(:doc) do
      Leptris::XML.parse('<?xml version="1.0" encoding="UTF-8"?><r/>')
    end

    it "Document#declaration returns the node view when the state is set" do
      decl = doc.declaration
      expect(decl).to be_a(Leptris::XML::Declaration)
      expect(decl.document).to equal(doc)
    end

    it "Document#declaration returns nil when unset" do
      expect(Leptris::XML.parse("<r/>").declaration).to be_nil
    end

    it "reads version/encoding/standalone" do
      decl = doc.declaration
      expect(decl.version).to eq("1.0")
      expect(decl.encoding).to eq("UTF-8")
      expect(decl.standalone).to be_nil
    end

    it "children list the declaration first" do
      names = doc.children
      expect(names.first).to be_a(Leptris::XML::Declaration)
      expect(names[1].name).to eq("r")
    end

    it "mutating the node changes the document state" do
      decl = doc.declaration
      decl.encoding = "UTF-16"
      expect(doc.xml_encoding).to eq("UTF-16")
      decl.standalone = true
      expect(doc.xml_standalone).to be(true)
      decl.version = "1.1"
      expect(doc.xml_version).to eq("1.1")
    end

    it "removing the node clears the state" do
      decl = doc.declaration
      decl.remove
      expect(doc.xml_version).to be_nil
      expect(doc.xml_encoding).to be_nil
      expect(doc.declaration).to be_nil
    end

    it "unlink is an alias of remove" do
      decl = doc.declaration
      decl.unlink
      expect(doc.declaration).to be_nil
    end

    it "repeated reads return the same object" do
      expect(doc.declaration).to equal(doc.declaration)
    end

    it "serializes to the declaration markup" do
      expect(doc.declaration.to_s)
        .to eq('<?xml version="1.0" encoding="UTF-8"?>')
    end

    it "answers to_xml — every child kind must (leptris#1732)" do
      expect(doc.declaration.to_xml)
        .to eq('<?xml version="1.0" encoding="UTF-8"?>')
    end

    it "to_xml accepts the serializer kwargs (leptris-ruby#477)" do
      decl = doc.declaration
      expect(decl.to_xml(indent: 2))
        .to eq('<?xml version="1.0" encoding="UTF-8"?>')
      expect(decl.to_xml(encoding: "UTF-8", no_decl: false))
        .to eq('<?xml version="1.0" encoding="UTF-8"?>')
    end

    it "to_xml answers empty under no_decl: — the preamble owns it (ruby#477)" do
      expect(doc.declaration.to_xml(no_decl: true)).to eq("")
    end

    it "survives moxml's repeatable children reads (ruby#477)" do
      doc2 = Leptris::XML.parse(
        '<?xml version="1.0" encoding="UTF-8"?><documents/>')
      2.times do
        doc2.children.each { |c| c.to_xml(indent: 2, no_decl: true) }
      end
      expect(doc2.children.first.to_xml(no_decl: true)).to eq("")
      expect(doc2.children.first.to_xml)
        .to eq('<?xml version="1.0" encoding="UTF-8"?>')
    end

    it "every document child answers to_xml (leptris#1732)" do
      doc2 = Leptris::XML.parse(
        '<?xml version="1.0" encoding="UTF-8"?><documents/>')
      expect(doc2.children.map(&:class).uniq.size).to be >= 2
      doc2.children.each(&:to_xml)
    end
  end

  describe "Detached DOCTYPE (ask 2)" do
    let(:doc) { Leptris::XML.parse("<r/>") }

    it "new_doctype builds an unattached DocType with readable ids" do
      dt = doc.new_doctype("r", public_id: "-//P//X", system_id: "s.dtd")
      expect(dt).to be_a(Leptris::XML::DocType)
      expect(dt.attached?).to be(false)
      expect(dt.name).to eq("r")
      expect(dt.public_id).to eq("-//P//X")
      expect(dt.system_id).to eq("s.dtd")
      expect(doc.doctype).to be_nil
    end

    it "attaching via add_child routes through set_doctype" do
      dt = doc.new_doctype("r", system_id: "s.dtd")
      doc.add_child(dt)
      expect(dt.attached?).to be(true)
      expect(doc.doctype.system_id).to eq("s.dtd")
      expect(doc.to_xml).to include("<!DOCTYPE r")
    end

    it "doc.doctype returns the same node identity after attach" do
      dt = doc.new_doctype("r")
      doc.add_child(dt)
      expect(doc.doctype).to equal(dt)
    end

    it "set_doctype still attaches immediately" do
      dt = doc.set_doctype("r", system_id: "s.dtd")
      expect(dt.attached?).to be(true)
      expect(doc.doctype).to equal(dt)
    end
  end
end
