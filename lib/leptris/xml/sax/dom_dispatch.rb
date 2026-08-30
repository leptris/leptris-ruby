# frozen_string_literal: true

# DOM-backed SAX dispatch (leptris-ruby#95): the engine's streaming
# attribute buffer corrupts leading attribute pairs when several
# nested ancestor levels each carry attributes — the callback
# transport, the recorder's packed arena, AND the pull parser all
# deliver the loss on the issue fixture (verified), while the DOM
# parser reads the same bytes correctly. Until the engine fix
# lands, SAX::Parser delivers from a DOM parse: same call shapes as
# the streaming transports — attach-only-overridden kinds,
# one-argument start_element arity, QName element names ("p:a"),
# UTF-8 strings, PI-data normalization.
#
# The walk is lean by construction: elements wrap (identity, name
# and prefix memos); every other child kind is read straight from
# its pointer — content getters per node type, never a wrapper.
module Leptris::XML::SAX::DomDispatch
  module_function

  def parse(handler, dispatched, string)
    doc = Leptris::XML::Document.parse(string)
    begin
      dispatch(handler, dispatched, doc)
    ensure
      doc.free
    end
  end

  def dispatch(handler, dispatched, doc)
    handler.start_document if dispatched[:start_document]
    doc_node = doc.node
    if doc_node
      visit_children(doc_node.c_ptr, doc, handler, dispatched,
                     element_parent: false)
    end
    handler.end_document if dispatched[:end_document]
    self
  end

  NODE = Leptris::XML::FFI
  ELEMENT = Leptris::XML::FFI::NODE_ELEMENT
  TEXT = Leptris::XML::FFI::NODE_TEXT
  COMMENT = Leptris::XML::FFI::NODE_COMMENT
  CDATA = Leptris::XML::FFI::NODE_CDATA
  PI = Leptris::XML::FFI::NODE_PI

  def visit_children(c_ptr, doc, handler, dispatched, element_parent: true)
    wants_text_kinds = dispatched[:characters] ||
                       dispatched[:comment] ||
                       dispatched[:cdata] || dispatched[:pi]
    if element_parent && !wants_text_kinds
      # Element-only handlers under an element: the element batch
      # hands out element pointers with no per-child get_type
      # (round XXIII's path) — text/comments/PIs are never fetched.
      # (The document node is not an element handle — the typed
      # walk serves it.)
      Leptris::XML::FFI.fetch_element_children(c_ptr).each do |child_ptr|
        visit_element(
          Leptris::XML::Node.wrap(child_ptr, doc, node_type: ELEMENT),
          handler, dispatched)
      end
      return
    end
    pointers, kinds = Leptris::XML::FFI.fetch_children(c_ptr)
    pointers.each_with_index do |child_ptr, i|
      case kinds[i]
      when ELEMENT
        visit_element(
          Leptris::XML::Node.wrap(child_ptr, doc, node_type: ELEMENT),
          handler, dispatched)
      when TEXT
        if dispatched[:characters]
          handler.characters(utf8(NODE.leptris_text_node_get_content(child_ptr)))
        end
      when CDATA
        if dispatched[:cdata]
          handler.cdata_block(utf8(NODE.leptris_cdata_node_get_content(child_ptr)))
        end
      when COMMENT
        if dispatched[:comment]
          handler.comment(utf8(NODE.leptris_comment_node_get_content(child_ptr)))
        end
      when PI
        if dispatched[:pi]
          handler.processing_instruction(
            utf8(NODE.leptris_pi_node_get_target(child_ptr)),
            Leptris::XML::FFI.read_pi_data(
              utf8(NODE.leptris_pi_node_get_data(child_ptr))))
        end
      end
    end
  end

  def visit_element(element, handler, dispatched)
    qname = element.prefix ? "#{element.prefix}:#{element.name}" : element.name
    if dispatched[:start_prefix]
      element.namespace_definitions.each do |ns|
        handler.start_prefix_mapping(ns.prefix.to_s, ns.href.to_s)
      end
    end
    if dispatched[:start_element]
      if dispatched[:start_element] == :one_arg
        handler.start_element(qname)
      else
        handler.start_element(qname, declared_pairs(element))
      end
    end
    visit_children(element.c_ptr, element.document, handler, dispatched)
    handler.end_element(qname) if dispatched[:end_element]
    if dispatched[:end_prefix]
      element.namespace_definitions.reverse_each do |ns|
        handler.end_prefix_mapping(ns.prefix.to_s)
      end
    end
  end

  # start_element's pairs with xmlns declarations carried — the
  # engine's streaming contract reports declarations among the
  # attribute pairs at their byte positions. Since libleptris
  # 1.9.18 (upstream #635, closing leptris-ruby#99's documented
  # difference), the raw qname-ordered list reproduces the exact
  # interleave.
  def declared_pairs(element)
    Leptris::XML::FFI.fetch_attributes_raw(element.c_ptr)
  end

  # [name, value] pairs in source order, read straight from the
  # attribute chain — no Attr objects, no hash.
  def attr_pairs(c_ptr)
    pairs = []
    attr = Leptris::XML::FFI.leptris_element_first_attribute(c_ptr)
    until attr.nil? || attr.null?
      pairs << [utf8(Leptris::XML::FFI.leptris_attribute_get_name(attr)),
                utf8(Leptris::XML::FFI.leptris_attribute_get_value(
                  c_ptr, attr))]
      attr = Leptris::XML::FFI.leptris_attribute_next(attr)
    end
    pairs
  end

  def utf8(str)
    str.nil? ? nil : str.force_encoding(Encoding::UTF_8)
  end
end
