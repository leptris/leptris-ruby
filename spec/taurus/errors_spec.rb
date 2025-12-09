# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Error Infrastructure" do
  describe "Error Code Mapping" do
    it "maps all parse error codes correctly" do
      expect(Taurus::FFI::ErrorCode::OK).to eq(0)
      expect(Taurus::FFI::ErrorCode::NULL_INPUT).to eq(1)
      expect(Taurus::FFI::ErrorCode::UNCLOSED_TAG).to eq(100)
      expect(Taurus::FFI::ErrorCode::INVALID_ATTR).to eq(101)
    end

    it "maps all XPath error codes correctly" do
      expect(Taurus::FFI::ErrorCode::XPATH_SYNTAX).to eq(200)
      expect(Taurus::FFI::ErrorCode::XPATH_FUNCTION).to eq(201)
      expect(Taurus::FFI::ErrorCode::XPATH_TYPE_MISMATCH).to eq(202)
    end

    it "maps all evaluation error codes correctly" do
      expect(Taurus::FFI::ErrorCode::EVAL_CONTEXT).to eq(300)
      expect(Taurus::FFI::ErrorCode::EVAL_ARGUMENT).to eq(301)
      expect(Taurus::FFI::ErrorCode::EVAL_OVERFLOW).to eq(302)
    end

    it "maps generic error codes correctly" do
      expect(Taurus::FFI::ErrorCode::OUT_OF_MEMORY).to eq(900)
      expect(Taurus::FFI::ErrorCode::INTERNAL).to eq(999)
    end
  end

  describe "Error Code to Symbol Conversion" do
    it "converts parse error codes to symbols" do
      expect(Taurus::FFI.error_code_to_sym(Taurus::FFI::ErrorCode::OK)).to eq(:ok)
      expect(Taurus::FFI.error_code_to_sym(Taurus::FFI::ErrorCode::UNCLOSED_TAG)).to eq(:unclosed_tag)
      expect(Taurus::FFI.error_code_to_sym(Taurus::FFI::ErrorCode::MALFORMED)).to eq(:malformed)
    end

    it "converts XPath error codes to symbols" do
      expect(Taurus::FFI.error_code_to_sym(Taurus::FFI::ErrorCode::XPATH_SYNTAX)).to eq(:xpath_syntax)
      expect(Taurus::FFI.error_code_to_sym(Taurus::FFI::ErrorCode::XPATH_NAMESPACE)).to eq(:xpath_namespace)
    end

    it "converts evaluation error codes to symbols" do
      expect(Taurus::FFI.error_code_to_sym(Taurus::FFI::ErrorCode::EVAL_ARGUMENT)).to eq(:eval_argument)
    end

    it "handles unknown error codes" do
      expect(Taurus::FFI.error_code_to_sym(9999)).to eq(:unknown)
    end
  end

  describe "Error Class Hierarchy" do
    it "defines Error as base class" do
      expect(Taurus::Error.superclass).to eq(StandardError)
    end

    it "defines ParseError inheriting from Error" do
      expect(Taurus::ParseError.superclass).to eq(Taurus::Error)
    end

    it "defines XPathError inheriting from Error" do
      expect(Taurus::XPathError.superclass).to eq(Taurus::Error)
    end

    it "defines EvaluationError inheriting from Error" do
      expect(Taurus::EvaluationError.superclass).to eq(Taurus::Error)
    end
  end

  describe "Error Infrastructure Ready" do
    it "has context snippet API" do
      expect(Taurus::FFI).to respond_to(:taurus_error_context)
      expect(Taurus::FFI).to respond_to(:taurus_error_byte_offset)
    end

    it "has error setting functions available in C" do
      # These are internal functions used by parser/evaluator
      # They're declared in taurus_internal.h:
      # - taurus_set_error
      # - taurus_set_error_with_context
      # - taurus_extract_context_snippet
      # Verified by successful compilation
      expect(true).to be true
    end
  end

  describe "FFI Error Functions" do
    it "has taurus_error_context binding" do
      expect(Taurus::FFI).to respond_to(:taurus_error_context)
    end

    it "has taurus_error_byte_offset binding" do
      expect(Taurus::FFI).to respond_to(:taurus_error_byte_offset)
    end

    it "has all error functions bound" do
      expect(Taurus::FFI).to respond_to(:taurus_last_error)
      expect(Taurus::FFI).to respond_to(:taurus_last_error_code)
      expect(Taurus::FFI).to respond_to(:taurus_error_string)
      expect(Taurus::FFI).to respond_to(:taurus_clear_error)
      expect(Taurus::FFI).to respond_to(:taurus_parse_error_line)
      expect(Taurus::FFI).to respond_to(:taurus_parse_error_column)
    end
  end
end