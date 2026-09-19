# frozen_string_literal: true

# The HTML facade (issue: "no HTML support in Ruby" — a discoverability
# gap, not a capability one). The engine has ONE DOM with multiple
# parser front-ends, so an HTML document IS a Leptris::XML::Document
# and every node/serializer/query face applies unchanged. What was
# missing was the shape porters scan for: a top-level HTML module
# mirroring the Nokogiri entry points.
#
#   Leptris::HTML(html)          # the html4 lane (Nokogiri::HTML parity)
#   Leptris::HTML5.parse(html)   # the WHATWG engine (html5lib zero reds)
#   Leptris::HTML4.parse(html)   # explicit html4 lane
#
# These are pure delegates — no parallel class hierarchy, no second
# wrapper cache; identity and the whole XML surface carry over.
module Leptris
  module HTML
    module_function

    # Nokogiri::HTML shape: the default lane is html4 (byte-parity
    # with libxml2/Nokogiri::HTML), matching XML.parse_html's default.
    def parse(html)
      Leptris::XML.parse_html(html, mode: :html4)
    end
  end

  module HTML4
    module_function

    def parse(html)
      Leptris::XML.parse_html(html, mode: :html4)
    end
  end

  module HTML5
    module_function

    # The conformant WHATWG engine: full implied-head set, foster
    # parenting, adoption agency, template, RCDATA/rawtext (see
    # spec/xml/html_whatwg_full_spec.rb).
    def parse(html)
      Leptris::XML.parse_html(html, mode: :whatwg)
    end
  end
end
