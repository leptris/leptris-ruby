# frozen_string_literal: true

# Node-shaped view of the document's XML declaration state
# (leptris-ruby#459 ask 1 — retires moxml's CustomizedLeptris value
# object). The engine stores the declaration as document state; this
# face reads and writes it in place. `remove`/`unlink` clears the
# state entirely (Document#clear_declaration).
class Leptris::XML::Declaration
  attr_reader :document

  def initialize(document)
    @document = document
  end

  def version
    @document.xml_version
  end

  def encoding
    @document.xml_encoding
  end

  def standalone
    @document.xml_standalone
  end

  def version=(value)
    @document.xml_version = value
    value
  end

  def encoding=(value)
    @document.xml_encoding = value
    value
  end

  def standalone=(value)
    @document.xml_standalone = value
    value
  end

  def remove
    @document.clear_declaration
    self
  end
  alias_method :unlink, :remove

  def to_s
    parts = ['<?xml version="' + version.to_s + '"']
    parts << 'encoding="' + encoding.to_s + '"' if encoding
    parts << 'standalone="' + (standalone ? "yes" : "no") + '"' unless standalone.nil?
    parts.join(" ") + "?>"
  end

  # The declaration rides Document#children (ruby#459), and generic
  # child serializers call to_xml on whatever children exist
  # (leptris#1732 — moxml's round trip). Same wire bytes as to_s.
  alias_method :to_xml, :to_s

  def inspect
    "#<#{self.class.name} version=#{version.inspect} " \
      "encoding=#{encoding.inspect} standalone=#{standalone.inspect}>"
  end
end
