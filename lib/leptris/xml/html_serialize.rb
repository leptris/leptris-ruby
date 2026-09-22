# frozen_string_literal: true

# The HTML5 tree serializer (#309): Ruby-level walk emitting
# HTML serialization semantics the XML face can't express —
#
# - VOID elements (br, meta, img, …) emit without the trailing
#   slash and without a closing tag (`<br>`, `<meta charset="utf-8">`)
# - script/style content is RAW TEXT — emitted verbatim, never
#   entity-escaped (`a > b` stays `a > b` inside `<style>`)
# - childless non-void elements get explicit closing tags
#   (`<div></div>`, never `<div/>`)
# - text escapes &, <, > (and U+00A0 as &nbsp;); attributes escape
#   &, ", <, >
#
# `Document#to_html` / `Element#to_html` are one-line delegates.
# The walk is Ruby-level by design for now — the engine-side
# serialization mode (raw-text + void handling in C) is the
# perf headroom this face gates on.
module Leptris::XML::HTMLSerialize
  VOID = %w[
    area base br col embed hr img input link meta param source
    track wbr
  ].freeze
  RAW_TEXT = %w[script style].freeze

  def self.document(doc)
    out = +""
    if (dt = doc.doctype)
      out << "<!DOCTYPE" << " #{dt.name}"
      out << " PUBLIC \"#{dt.public_id}\"" if dt.public_id
      out << " \"#{dt.system_id}\"" if dt.system_id
      out << ">"
    end
    doc.children.each { |child| node(child, out) }
    out
  end

  def self.element(element)
    out = +""
    node(element, out)
    out
  end

  def self.node(node, out)
    case node
    when Leptris::XML::Element then element_node(node, out)
    when Leptris::XML::Comment then out << "<!--" << node.content.to_s << "-->"
    when Leptris::XML::CDATA
      # HTML5: CDATA sections in HTML serialize as bogus comments.
      out << "<!--[CDATA[" << node.content.to_s << "]]-->"
    when Leptris::XML::ProcessingInstruction
      # HTML5: PIs serialize as bogus comments (?> is not a thing).
      out << "<?" << node.target.to_s
      out << " " << node.data.to_s unless node.data.to_s.empty?
      out << ">"
    when Leptris::XML::Text then text(node, out)
    end
  end

  def self.element_node(el, out)
    name = el.name
    out << "<" << name
    el.attributes.each do |attr_name, attr|
      out << " " << attr_name << "=\"" << escape_attr(attr.value) << "\""
    end
    out << ">"
    return if VOID.include?(name)

    if RAW_TEXT.include?(name)
      # Raw text: the element's text content verbatim — no entity
      # escaping (CSS child selectors, JS comparisons survive).
      el.children.each do |child|
        out << child.content.to_s if child.is_a?(Leptris::XML::Text)
      end
    else
      el.children.each { |child| node(child, out) }
    end
    out << "</" << name << ">"
  end

  def self.text(node, out)
    parent_raw = node.parent && RAW_TEXT.include?(node.parent.name)
    s = node.content.to_s
    out << (parent_raw ? s : escape_text(s))
  end

  def self.escape_text(s)
    s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
     .gsub("\u00A0", "&nbsp;")
  end

  def self.escape_attr(s)
    s.to_s.gsub("&", "&amp;").gsub("\"", "&quot;")
          .gsub("<", "&lt;").gsub(">", "&gt;")
          .gsub("\u00A0", "&nbsp;")
  end
end
