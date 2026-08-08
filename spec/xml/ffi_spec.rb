# frozen_string_literal: true

require "taurus/xml"

RSpec.describe Taurus::XML::FFI do
  describe "library loading" do
    it "is attached to libtaurus shared library" do
      expect(described_class).to be_a(Module)
    end

    it "exposes taurus_version as an attached function" do
      expect(described_class).to respond_to(:taurus_version)
    end

    it "returns a version string from taurus_version" do
      version = described_class.taurus_version
      expect(version).to be_a(String)
      expect(version).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe "document lifecycle" do
    it "attaches taurus_parse_string and taurus_document_free" do
      expect(described_class).to respond_to(:taurus_parse_string)
      expect(described_class).to respond_to(:taurus_document_free)
      expect(described_class).to respond_to(:taurus_document_root)
    end

    it "attaches taurus_document_serialize and taurus_element_serialize" do
      expect(described_class).to respond_to(:taurus_document_serialize)
      expect(described_class).to respond_to(:taurus_element_serialize)
    end

    it "attaches taurus_c14n_canonicalize" do
      expect(described_class).to respond_to(:taurus_c14n_canonicalize)
    end
  end

  describe "node traversal" do
    it "attaches the taurus_node_* family" do
      %i[
        taurus_node_get_type
        taurus_node_first_child
        taurus_node_last_child
        taurus_node_next_sibling
        taurus_node_previous_sibling
        taurus_node_child_count
        taurus_node_as_element
        taurus_element_as_node
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end
  end

  describe "element operations" do
    it "attaches element query functions" do
      %i[
        taurus_element_name
        taurus_element_text
        taurus_element_attribute
        taurus_element_attribute_count
        taurus_element_attribute_name_at
        taurus_element_attribute_value_at
        taurus_element_parent
        taurus_element_first_child_any
        taurus_element_last_child_any
        taurus_element_next_sibling_any
        taurus_element_previous_sibling_any
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end

    it "attaches element mutation functions" do
      %i[
        taurus_element_create
        taurus_element_set_name
        taurus_element_set_attribute
        taurus_element_remove_attribute
        taurus_element_remove_child
        taurus_element_remove_children
        taurus_element_append_child
        taurus_element_prepend_child
        taurus_element_insert_before
        taurus_element_insert_after
        taurus_element_set_text
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end
  end

  describe "typed-node content getters" do
    it "attaches content getters for text/comment/cdata/pi" do
      %i[
        taurus_text_node_get_content
        taurus_comment_node_get_content
        taurus_cdata_node_get_content
        taurus_pi_node_get_target
        taurus_pi_node_get_data
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end
  end

  describe "XPath" do
    it "attaches the full xpath surface" do
      %i[
        taurus_xpath_eval
        taurus_xpath_eval_with_vars
        taurus_xpath_result_type
        taurus_xpath_result_count
        taurus_xpath_result_get
        taurus_xpath_result_boolean
        taurus_xpath_result_number
        taurus_xpath_result_string
        taurus_xpath_result_free
        taurus_xpath_variable_set_new
        taurus_xpath_variable_set_free
        taurus_xpath_variable_set_boolean
        taurus_xpath_variable_set_number
        taurus_xpath_variable_set_string
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end
  end

  describe "SAX" do
    it "attaches the sax surface" do
      %i[
        taurus_sax_parse
        taurus_sax_parser_create
        taurus_sax_parser_feed
        taurus_sax_parser_free
        taurus_sax_parser_set_streaming
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
        taurus_element_namespace
        taurus_namespace_uri
        taurus_namespace_prefix
        taurus_element_namespace_for_prefix
        taurus_element_namespace_count
      ].each do |fn|
        expect(described_class).to respond_to(fn), "missing #{fn}"
      end
    end
  end

  describe "memory + status" do
    it "attaches taurus_free_string and taurus_xinclude_process" do
      expect(described_class).to respond_to(:taurus_free_string)
      expect(described_class).to respond_to(:taurus_xinclude_process)
    end

    it "exposes status code constants" do
      expect(described_class::TAURUS_OK).to eq(0)
      expect(described_class::TAURUS_ERROR_PARSE).to eq(-2)
      expect(described_class::TAURUS_ERROR_XPATH).to eq(-3)
    end

    it "exposes xpath result type constants" do
      expect(described_class::XPATH_NODESET).to eq(0)
      expect(described_class::XPATH_BOOLEAN).to eq(1)
      expect(described_class::XPATH_NUMBER).to eq(2)
      expect(described_class::XPATH_STRING).to eq(3)
    end

    it "exposes libtaurus raw node type constants" do
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
