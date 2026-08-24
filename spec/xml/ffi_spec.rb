# frozen_string_literal: true

require "leptris/xml"

RSpec.describe Leptris::XML::FFI do
  describe "library loading" do
    it "is attached to libleptris shared library" do
      expect(described_class).to be_a(Module)
    end

    it "exposes leptris_version as an attached function" do
      expect(described_class).to respond_to(:leptris_version)
    end

    it "returns a version string from leptris_version" do
      version = described_class.leptris_version
      expect(version).to be_a(String)
      expect(version).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe "document lifecycle" do
    it "attaches leptris_parse_string and leptris_document_free" do
      expect(described_class).to respond_to(:leptris_parse_string)
      expect(described_class).to respond_to(:leptris_document_free)
      expect(described_class).to respond_to(:leptris_document_root)
    end

    it "attaches leptris_document_serialize and leptris_element_serialize" do
      expect(described_class).to respond_to(:leptris_document_serialize)
      expect(described_class).to respond_to(:leptris_element_serialize)
    end

    it "attaches leptris_c14n_canonicalize" do
      expect(described_class).to respond_to(:leptris_c14n_canonicalize)
    end
  end

  describe "node traversal" do
    it "attaches the leptris_node_* family" do
      %i[
        leptris_node_get_type
        leptris_node_first_child
        leptris_node_last_child
        leptris_node_next_sibling
        leptris_node_previous_sibling
        leptris_node_child_count
        leptris_node_as_element
        leptris_element_as_node
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end
  end

  describe "element operations" do
    it "attaches element query functions" do
      %i[
        leptris_element_name
        leptris_element_text
        leptris_element_attribute
        leptris_element_attribute_count
        leptris_element_attribute_name_at
        leptris_element_attribute_value_at
        leptris_element_parent
        leptris_element_first_child_any
        leptris_element_last_child_any
        leptris_element_next_sibling_any
        leptris_element_previous_sibling_any
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end

    it "attaches element mutation functions" do
      %i[
        leptris_element_create
        leptris_element_set_name
        leptris_element_set_attribute
        leptris_element_remove_attribute
        leptris_element_remove_child
        leptris_element_remove_children
        leptris_element_append_child
        leptris_element_prepend_child
        leptris_element_insert_before
        leptris_element_insert_after
        leptris_element_set_text
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end
  end

  describe "typed-node content getters" do
    it "attaches content getters for text/comment/cdata/pi" do
      %i[
        leptris_text_node_get_content
        leptris_comment_node_get_content
        leptris_cdata_node_get_content
        leptris_pi_node_get_target
        leptris_pi_node_get_data
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end
  end

  describe "XPath" do
    it "attaches the full xpath surface" do
      %i[
        leptris_xpath_eval
        leptris_xpath_eval_with_vars
        leptris_xpath_result_type
        leptris_xpath_result_count
        leptris_xpath_result_boolean
        leptris_xpath_result_number
        leptris_xpath_result_string
        leptris_xpath_result_free
        leptris_xpath_variable_set_new
        leptris_xpath_variable_set_free
        leptris_xpath_variable_set_boolean
        leptris_xpath_variable_set_number
        leptris_xpath_variable_set_string
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end
  end

  describe "SAX" do
    it "attaches the sax surface" do
      %i[
        leptris_sax_parse
        leptris_sax_parser_create
        leptris_sax_parser_feed
        leptris_sax_parser_free
        leptris_sax_parser_set_streaming
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end

    it "exposes the SAXHandler struct class" do
      expect(described_class::SAXHandler).to be < ::FFI::Struct
    end

    it "exposes the SerializeOptions struct class" do
      expect(described_class::SerializeOptions).to be < ::FFI::Struct
    end
  end

  describe "namespaces" do
    it "attaches namespace accessors" do
      %i[
        leptris_element_namespace
        leptris_namespace_uri
        leptris_namespace_prefix
        leptris_element_namespace_for_prefix
        leptris_element_namespace_count
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end
  end

  describe "memory + status" do
    it "attaches leptris_free_string and leptris_xinclude_process" do
      expect(described_class).to respond_to(:leptris_free_string)
      expect(described_class).to respond_to(:leptris_xinclude_process)
    end

    it "exposes status code constants" do
      expect(described_class::LEPTRIS_OK).to eq(0)
      expect(described_class::LEPTRIS_ERROR_PARSE).to eq(-2)
      expect(described_class::LEPTRIS_ERROR_XPATH).to eq(-3)
    end

    it "exposes xpath result type constants" do
      expect(described_class::XPATH_NODESET).to eq(0)
      expect(described_class::XPATH_BOOLEAN).to eq(1)
      expect(described_class::XPATH_NUMBER).to eq(2)
      expect(described_class::XPATH_STRING).to eq(3)
    end

    it "exposes libleptris raw node type constants" do
      expect(described_class::NODE_ELEMENT).to eq(0)
      expect(described_class::NODE_TEXT).to eq(1)
      expect(described_class::NODE_COMMENT).to eq(2)
      expect(described_class::NODE_CDATA).to eq(3)
      expect(described_class::NODE_PI).to eq(4)
      expect(described_class::NODE_DOCTYPE).to eq(5)
      expect(described_class::NODE_ATTRIBUTE).to eq(6)
    end

    it "exposes C14N version constants" do
      expect(described_class::C14N_1_0).to eq(0)
      expect(described_class::C14N_1_1).to eq(1)
    end
  end
end
