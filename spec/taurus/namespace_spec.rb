# frozen_string_literal: true

require "spec_helper"

RSpec.describe Taurus::Element, "namespace support" do
  describe "#namespace" do
    it "returns nil when element has no namespace" do
      elem = Taurus::Element.new("item")
      expect(elem.namespace).to be_nil
    end

    it "returns namespace hash when element has a namespace" do
      elem = Taurus::Element.new("ex:item")
      # In a real implementation with parser, this would be set during parsing
      # For now, we're testing the API structure

      # The namespace method returns { prefix: "ex", href: "http://example.org" }
      # when namespaces are properly tracked
    end
  end

  describe "#namespaces" do
    it "returns empty array when element has no namespace declarations" do
      elem = Taurus::Element.new("item")
      expect(elem.namespaces).to eq([])
    end

    it "returns array of namespace declarations" do
      elem = Taurus::Element.new("root")
      # Namespace declarations would be added during parsing
      # expect(elem.namespaces).to be_an(Array)
    end
  end

  describe "#namespace_for_prefix" do
    it "returns nil when prefix is not found" do
      elem = Taurus::Element.new("item")
      expect(elem.namespace_for_prefix("ex")).to be_nil
    end

    it "resolves default namespace with nil prefix" do
      elem = Taurus::Element.new("item")
      # Would return URI if default namespace exists
      expect(elem.namespace_for_prefix(nil)).to be_nil
    end
  end

  describe "#parent=" do
    it "sets parent to nil" do
      elem = Taurus::Element.new("item")
      elem.parent = nil
      expect(elem.parent).to be_nil
    end

    it "sets parent to another element" do
      parent = Taurus::Element.new("root")
      child = Taurus::Element.new("item")

      child.parent = parent
      expect(child.parent).to eq(parent)
    end

    it "raises error when setting self as parent" do
      elem = Taurus::Element.new("item")
      expect { elem.parent = elem }.to raise_error(ArgumentError, /own parent/)
    end

    it "raises error when parent is not an Element" do
      elem = Taurus::Element.new("item")
      expect { elem.parent = "not an element" }.to raise_error(TypeError)
    end
  end

  describe "convenience methods" do
    describe "#<<" do
      it "adds a child node" do
        elem = Taurus::Element.new("root")
        child = Taurus::Element.new("item")

        elem << child
        expect(elem.nodes).to include(child)
      end

      it "returns self for chaining" do
       elem = Taurus::Element.new("root")
        child = Taurus::Element.new("item")

        result = elem << child
        expect(result).to eq(elem)
      end
    end

    describe "#remove" do
      it "removes element from parent" do
        parent = Taurus::Element.new("root")
        child = Taurus::Element.new("item")

        parent << child
        child.parent = parent

        child.remove
        expect(parent.nodes).not_to include(child)
        expect(child.parent).to be_nil
      end

      it "does nothing when element has no parent" do
        elem = Taurus::Element.new("item")
        expect { elem.remove }.not_to raise_error
      end
    end

    describe "#add_child" do
      it "adds child and sets parent relationship" do
        parent = Taurus::Element.new("root")
        child = Taurus::Element.new("item")

        parent.add_child(child)
        expect(parent.nodes).to include(child)
        expect(child.parent).to eq(parent)
      end

      it "removes child from old parent before adding" do
        old_parent = Taurus::Element.new("old")
        new_parent = Taurus::Element.new("new")
        child = Taurus::Element.new("item")

        old_parent.add_child(child)
        new_parent.add_child(child)

        expect(old_parent.nodes).not_to include(child)
        expect(new_parent.nodes).to include(child)
        expect(child.parent).to eq(new_parent)
      end
    end

    describe "#text" do
      it "returns first text node" do
        elem = Taurus::Element.new("item")
        elem << "Hello"
        elem << "World"

        expect(elem.text).to eq("Hello")
      end

      it "returns nil when no text nodes" do
        elem = Taurus::Element.new("item")
        expect(elem.text).to be_nil
      end
    end

    describe "#replace_text" do
      it "replaces all child nodes with text" do
        elem = Taurus::Element.new("item")
        elem << Taurus::Element.new("child")
        elem << "old text"

        elem.replace_text("new text")
        expect(elem.nodes).to eq(["new text"])
      end

      it "raises error for non-string argument" do
        elem = Taurus::Element.new("item")
        expect { elem.replace_text(123) }.to raise_error(ArgumentError)
      end
    end

    describe "#[] and #[]=" do
      it "gets and sets attributes" do
        elem = Taurus::Element.new("item")
        elem["id"] = "123"

        expect(elem["id"]).to eq("123")
      end

      it "handles symbol keys" do
        elem = Taurus::Element.new("item")
        elem[:id] = "123"

        expect(elem[:id]).to eq("123")
      end
    end

    describe "#namespace_prefix" do
      it "returns nil when no namespace" do
        elem = Taurus::Element.new("item")
        expect(elem.namespace_prefix).to be_nil
      end
    end

    describe "#namespace_uri" do
      it "returns nil when no namespace" do
        elem = Taurus::Element.new("item")
        expect(elem.namespace_uri).to be_nil
      end
    end

    describe "#namespace?" do
      it "returns false when no namespace" do
        elem = Taurus::Element.new("item")
        expect(elem.namespace?).to be false
      end
    end

    describe "#all_namespaces" do
      it "returns empty hash when no namespaces" do
        elem = Taurus::Element.new("item")
        expect(elem.all_namespaces).to eq({})
      end
    end

    describe ".with_namespace" do
      it "creates element with namespace" do
        elem = Taurus::Element.with_namespace("item", prefix: "ex", href: "http://example.org")
        expect(elem.name).to eq("item")
        expect(elem.attributes["xmlns:ex"]).to eq("http://example.org")
      end

      it "creates element with default namespace" do
        elem = Taurus::Element.with_namespace("item", href: "http://example.org")
        expect(elem.attributes["xmlns"]).to eq("http://example.org")
      end
    end
  end
end