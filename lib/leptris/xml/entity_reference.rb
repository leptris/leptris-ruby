# frozen_string_literal: true

# An unexpanded &name; entity reference — a first-class node when
# parsing with ParseOptions.keep_entity_refs (libleptris 1.9.176,
# upstream #1094 / leptris-ruby#212), or created via
# Document#create_entity_reference. Serializes back verbatim as
# &name;; text runs around it split into their own Text siblings.
class Leptris::XML::EntityReference < Leptris::XML::Node
  def name
    Leptris::XML::FFI.leptris_entity_ref_node_name(c_ptr)
  end
  alias_method :node_name, :name
end
