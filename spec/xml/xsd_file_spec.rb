# frozen_string_literal: true

require "spec_helper"
require "tempfile"

# libleptris 1.9.326: the file-path compile face — unreadable
# files raise; malformed schemas compile to an error-carrying
# handle, exactly like the string face.
RSpec.describe "XSD.compile_file (1.9.326)" do
  it "compiles from a path and validates" do
    f = Tempfile.new(["schema", ".xsd"])
    f.write(<<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="r"/>
      </xs:schema>
    XSD
    f.close
    schema = Leptris::XML::XSD.compile_file(f.path)
    expect(schema.declaration_count).to eq(1)
    expect(schema.error).to be_nil
    f.unlink
  end

  it "raises on unreadable paths" do
    expect { Leptris::XML::XSD.compile_file("/nonexistent/xsd-#{rand(1e6)}.xsd") }
      .to raise_error(Leptris::XML::Error, /unreadable/)
  end
end
