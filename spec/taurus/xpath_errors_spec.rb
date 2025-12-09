# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'XPath Error Messages' do
  let(:xml) { '<root><item id="1">text</item><item id="2">more</item></root>' }
  let(:doc) { Taurus.parse(xml) }

  describe 'Syntax Errors' do
    it 'reports incomplete path with position' do
      expect {
        doc.xpath('//')  # Incomplete path - missing node test
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.message).to include('Expected')
        expect(error.code).to eq(:xpath_syntax)
        expect(error.line).to be > 0
        expect(error.column).to be > 0
        expect(error.context).not_to be_nil
      end
    end

    it 'reports unclosed predicate' do
      expect {
        doc.xpath('//item[')  # Unclosed predicate
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_syntax)
        expect(error.message).to include("Unexpected token")
        expect(error.line).to eq(1)
      end
    end

    it 'reports unclosed parenthesis' do
      expect {
        doc.xpath('//item[position(')  # Unclosed function call
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_syntax)
        expect(error.message).to include("Unexpected token")
      end
    end

    it 'reports unexpected token after complete expression' do
      expect {
        doc.xpath('//item ]')  # Extra closing bracket
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_syntax)
        expect(error.message).to include('Unexpected token')
        expect(error.column).to be > 0
      end
    end

    it 'reports incomplete expression in predicate' do
      expect {
        doc.xpath('//item[@id = 1 and ]')  # Incomplete and expression
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_syntax)
        expect(error.line).to eq(1)
      end
    end

    it 'reports unterminated string literal' do
      expect {
        doc.xpath("//item[@id = 'test")  # Missing closing quote
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_syntax)
        expect(error.message).to include('Unexpected token')
      end
    end

    it 'reports invalid character in expression' do
      expect {
        doc.xpath('//item[@id = #123]')  # Invalid # character
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_syntax)
        expect(error.message).to include('Unexpected token')
      end
    end

    it 'reports unexpected colon outside QName' do
      expect {
        doc.xpath('//item/:child')  # Invalid bare colon
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_syntax)
        expect(error.message).to include('node test')
      end
    end

    it 'reports unexpected exclamation mark' do
      expect {
        doc.xpath('//item[!]')  # Invalid ! without =
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_syntax)
        expect(error.message).to include('Unexpected token')
      end
    end
  end

  describe 'Unknown Function Errors' do
    it 'reports unknown function name' do
      expect {
        doc.xpath('unknown-function()')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.message).to include('unknown-function')
        expect(error.code).to eq(:xpath_function)
      end
    end

    it 'reports unknown function with position' do
      expect {
        doc.xpath('not_a_real_xpath_function_xyz()')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_function)
        expect(error.line).to eq(1)
        expect(error.column).to be > 0
      end
    end
  end

  describe 'Error Context Snippets' do
    it 'shows context for syntax errors at start' do
      expect {
        doc.xpath('[invalid')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.context).not_to be_nil
        expect(error.context).to include('[invalid')
      end
    end

    it 'shows context for errors in middle of expression' do
      expect {
        doc.xpath('//item[@id = 1 and @name = ]')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.context).not_to be_nil
        # Should show context around the error position
        expect(error.context.length).to be > 0
      end
    end

    it 'shows context for errors at end of expression' do
      expect {
        doc.xpath('//item[@id =')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.context).not_to be_nil
        expect(error.context).to include('@id')
      end
    end

    it 'includes error position marker in context' do
      expect {
        doc.xpath('//item[')
      }.to raise_error(Taurus::XPathError) do |error|
        # Context should include a position marker (e.g., ^)
        expect(error.context).to match(/\^|\|/)
      end
    end
  end

  describe 'Position Tracking Accuracy' do
    it 'reports correct line for single-line expressions' do
      expect {
        doc.xpath('//item[@invalid')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.line).to eq(1)
      end
    end

    it 'reports correct column for early errors' do
      expect {
        doc.xpath('[')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.column).to eq(1)
      end
    end

    it 'reports correct column for mid-expression errors' do
      expect {
        doc.xpath('//item[@id = &]')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.column).to be_between(14, 16)
      end
    end

    it 'reports correct position for EOF errors' do
      expect {
        doc.xpath('//item[position()')  # Missing closing ]
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.line).to eq(1)
        expect(error.column).to be > 15
      end
    end
  end

  describe 'Multiple Error Scenarios' do
    it 'reports first error when multiple issues exist' do
      expect {
        doc.xpath('//item[[@id]')  # Double [[ - first error should be reported
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_syntax)
        # Should report the first [ issue
      end
    end

    it 'provides helpful message for common mistakes' do
      expect {
        doc.xpath('//item[!@id]')  # Should be 'not(@id)'
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.message).to include('Unexpected token')
      end
    end
  end

  describe 'Error Message Quality' do
    it 'includes expression text in error for short expressions' do
      expect {
        doc.xpath('[')
      }.to raise_error(Taurus::XPathError) do |error|
        # Context should include the invalid expression
        expect(error.context).to include('[')
      end
    end

    it 'provides clear description of what was expected' do
      expect {
        doc.xpath('//item[')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.message).to match(/expected|missing/i)
      end
    end

    it 'identifies token type that caused error' do
      expect {
        doc.xpath('//item ]')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.message).to include('RBRACKET')
      end
    end
  end

  describe 'Regression Tests' do
    it 'handles valid expressions without errors' do
      expect { doc.xpath('//item') }.not_to raise_error
      expect { doc.xpath('//item[@id]') }.not_to raise_error
      expect { doc.xpath('//item[1]') }.not_to raise_error
      expect { doc.xpath('//item[@id="1"]') }.not_to raise_error
    end

    it 'maintains existing XPath functionality' do
      result = doc.xpath('//item[@id="1"]')
      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
    end
  end

  describe 'Edge Cases' do
    it 'handles empty expression' do
      expect {
        doc.xpath('')
      }.to raise_error(Taurus::ParseError) do |error|
        expect(error.code).to eq(:empty_input)
      end
    end

    it 'handles whitespace-only expression' do
      expect {
        doc.xpath('   ')
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.code).to eq(:xpath_syntax)
      end
    end

    it 'handles very long error positions correctly' do
      long_path = '//item' + ('[@id]' * 50) + '['
      expect {
        doc.xpath(long_path)
      }.to raise_error(Taurus::XPathError) do |error|
        expect(error.line).to eq(1)
        expect(error.column).to be > 100
      end
    end
  end
end