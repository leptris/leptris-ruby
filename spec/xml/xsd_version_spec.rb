# frozen_string_literal: true

require "spec_helper"

# The face rides the engine (libleptris 1.9.382+); older engine
# installs take a skip.
RSpec.describe "Leptris::XML::XSD::Schema#version",
               if: defined?(Leptris::XML::XSD) &&
                   Leptris::XML::XSD.respond_to?(:compile) do
  def compile(src)
    Leptris::XML::XSD.compile(src)
  end

  it 'answers "1.1" when the root declares @version="1.1"' do
    schema = compile(
      '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"' \
      ' version="1.1">' \
      '<xs:element name="e" type="xs:string"/></xs:schema>'
    )
    expect(schema.version).to eq("1.1")
  end

  it 'answers "1.0" for an untagged schema' do
    schema = compile(
      '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">' \
      '<xs:element name="e" type="xs:string"/></xs:schema>'
    )
    expect(schema.version).to eq("1.0")
  end
end
