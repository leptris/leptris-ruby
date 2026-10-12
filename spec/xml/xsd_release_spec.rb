# frozen_string_literal: true

require "spec_helper"

# Schema#release (moxml#362.3): deterministic drop of the compiled
# schema — long-lived validation services stop parking engine-side
# trees for the process lifetime. The AutoPointer's GC finalizer
# disarms first, so the free happens exactly once.
RSpec.describe "Leptris::XML::XSD::Schema#release" do
  let(:schema_text) do
    <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="a" type="xs:string"/>
      </xs:schema>
    XSD
  end

  it "frees the handle deterministically and reports the state" do
    schema = Leptris::XML::XSD.compile(schema_text)
    expect(schema.declaration_count).to eq(1)
    expect(schema.release).to be(true)
    expect(schema.released?).to be(true)
  end

  it "raises on faces after release" do
    schema = Leptris::XML::XSD.compile(schema_text)
    schema.release
    expect { schema.declaration_count }
      .to raise_error(Leptris::XML::UseAfterFreeError, /released/)
    expect { schema.valid?(nil) }
      .to raise_error(Leptris::XML::UseAfterFreeError, /released/)
  end

  it "is idempotent and GC-safe after release" do
    schema = Leptris::XML::XSD.compile(schema_text)
    expect(schema.release).to be(true)
    expect(schema.release).to be(true)
    GC.start
    expect(schema.released?).to be(true)
  end
end
