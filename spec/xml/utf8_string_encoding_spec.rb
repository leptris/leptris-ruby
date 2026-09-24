# frozen_string_literal: true

require "spec_helper"

# FFI's :string return type tags returned bytes ASCII-8BIT; every
# string libleptris hands back is character data (UTF-8, the XML
# default), so the FFI layer converts all string returns to UTF-8.
# Consumers interpolate and regex these values against UTF-8 Ruby
# literals — a binary tag raises Encoding::CompatibilityError there
# and silently diverges in gsub/line-ending code (lutaml-model#858).
RSpec.describe "UTF-8 string encoding across the FFI surface" do
  let(:xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Relationship Id="rId5" Title="café – naïve">
        <Target>http://example.com/x?n=é</Target>
      </Relationship>
    XML
  end

  let(:doc) { Leptris::XML::Document.parse(xml) }
  let(:root) { doc.root }

  it "tags element names UTF-8" do
    expect(root.name.encoding).to eq(Encoding::UTF_8)
  end

  it "tags attribute names and values UTF-8" do
    root.attributes.each_value do |attr|
      expect(attr.name.encoding).to eq(Encoding::UTF_8)
      expect(attr.value.encoding).to eq(Encoding::UTF_8)
    end
  end

  it "tags text content UTF-8" do
    target = root.children.find { |c| c.name == "Target" }
    expect(target.text.encoding).to eq(Encoding::UTF_8)
  end

  it "tags attribute_pairs values UTF-8" do
    root.attribute_pairs.each do |name, value|
      expect(name.encoding).to eq(Encoding::UTF_8)
      expect(value.encoding).to eq(Encoding::UTF_8)
    end
  end

  it "tags plan-walk attribute and scalar values UTF-8" do
    descriptor = Leptris::XML::Descriptor.build(
      name: "Relationship",
      attributes: [{ name: "Id", kind: :scalar }, { name: "Title", kind: :scalar }],
      children: [{ name: "Target", kind: :scalar }],
    )
    value = descriptor.walk(root)

    expect(value.attribute("Id").encoding).to eq(Encoding::UTF_8)
    expect(value.attribute("Title").encoding).to eq(Encoding::UTF_8)
  end

  it "interpolates against UTF-8 literals without raising" do
    value = root.attributes["Title"].value
    expect { "prefix: #{value}" }.not_to raise_error
    expect("prefix: #{value}").to eq("prefix: café – naïve")
  end
end
