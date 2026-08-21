# frozen_string_literal: true

class Leptris::XML::SAX::Document
  # Called when an XML declaration is parsed.
  def xmldecl(version, encoding, standalone)
  end

  def start_document
  end

  def end_document
  end

  # Called at the beginning of an element.
  # +attrs+ is an Array of [name, value] pairs in source order.
  def start_element(name, attrs = [])
  end

  def end_element(name)
  end

  def characters(string)
  end

  def comment(string)
  end

  def cdata_block(string)
  end

  def processing_instruction(name, content)
  end

  def start_prefix_mapping(prefix, uri)
  end

  def end_prefix_mapping(prefix)
  end

  def warning(string)
  end

  def error(message, line = 0, column = 0)
  end
end
