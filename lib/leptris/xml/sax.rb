# frozen_string_literal: true

require "ffi"

module Leptris
  module XML
    module SAX
      autoload :Document, "leptris/xml/sax/document"
      autoload :Parser, "leptris/xml/sax/parser"
      autoload :Recorder, "leptris/xml/sax/recorder"
      autoload :DomDispatch, "leptris/xml/sax/dom_dispatch"
    end
  end
end
