# frozen_string_literal: true

# Markup-accumulating subtree construction (#374 lever 2): the
# builder turns a Ruby block into well-formed markup in a plain
# String (Ruby-side cost only), and the flush performs ONE native
# crossing — parse + attach — for the whole subtree. The
# per-element FFI crossing that dominated the object-face build
# profile collapses to one per #build call.
#
#     doc.build do |b|
#       b.catalog(id: "c") do
#         b.item(id: 7) { b.name "Item 7" }
#       end
#     end
#
# Element names arriving through method_missing are identifier-
# shaped by construction (Ruby method names cannot carry markup
# metacharacters); the explicit #element path checks NAME_RE.
# Text and attribute values escape in one pass per string.
class Leptris::XML::Builder
  NAME_RE = /\A[a-zA-Z_][\w.-]*\z/

  ESCAPE = {
    "&" => "&amp;",
    "<" => "&lt;",
    ">" => "&gt;",
    '"' => "&quot;",
  }.freeze
  ESCAPE_RE = /[&<>"]/
  private_constant :ESCAPE, :ESCAPE_RE

  # +sink+ receives the flushed markup (a Document or Element).
  def initialize(sink)
    @sink = sink
    @buf = +""
    @depth = 0
  end

  def element(name, attributes = nil)
    name = name.to_s
    unless name =~ NAME_RE
      raise ArgumentError,
        "element name must match #{NAME_RE.inspect}, got #{name.inspect}"
    end
    @buf << "<" << name
    write_attributes(attributes) if attributes
    if block_given?
      @buf << ">"
      @depth += 1
      begin
        yield self
      ensure
        @depth -= 1
      end
      @buf << "</" << name << ">"
    else
      @buf << "/>"
    end
    self
  end

  def text(content)
    @buf << escape_text(content.to_s)
    self
  end

  def cdata(content)
    @buf << "<![CDATA[" << content.to_s << "]]>"
    self
  end

  def comment(content)
    @buf << "<!--" << escape_text(content.to_s) << "-->"
    self
  end

  # Verbatim markup — the escape hatch for pre-serialized
  # fragments; the caller owns well-formedness.
  def raw(markup)
    @buf << markup.to_s
    self
  end

  def method_missing(name, *args, &block)
    # Method names are identifier-shaped: they cannot carry <, >,
    # &, quotes, or whitespace, so they need no NAME_RE round-trip
    # (trailing = / ? / ! are legal Ruby but never legal XML
    # name tails here — reject them explicitly).
    return super if name.to_s.end_with?("=", "?", "!")
    case args.length
    when 0
      element(name.to_s, &block)
    when 1
      arg = args[0]
      if arg.is_a?(Hash)
        element(name.to_s, arg, &block)
      else
        element(name.to_s) { |b| b.text(arg); block&.call(b) }
      end
    when 2
      attrs, txt = args
      return super unless attrs.is_a?(Hash)
      element(name.to_s, attrs) { |b| b.text(txt); block&.call(b) }
    else
      super
    end
  end

  def respond_to_missing?(name, include_private = false)
    !name.to_s.end_with?("=", "?", "!") || super
  end

  # One native crossing for the accumulated subtree: the flush
  # parses + attaches. Document sinks take exactly one root
  # (set_root_ex adopts the parsed root); element sinks append
  # every fragment child.
  def flush
    unless @depth.zero?
      raise Leptris::XML::Error,
        "unbalanced builder — unclosed elements remain (depth #{@depth})"
    end
    markup = @buf
    return @sink if markup.empty?
    case @sink
    when Leptris::XML::Document
      parsed = Leptris::XML::Document.parse(markup)
      root = parsed.root
      if root.nil?
        raise Leptris::XML::Error,
          "builder markup produced no root element"
      end
      @sink.root = root
      @buf = +""
      # The INSTALLED root — the same wrapper #root now yields
      # (root= returns the parsed source, not the adoption copy).
      @sink.root
    when Leptris::XML::Element
      added = @sink.add_child(markup)
      @buf = +""
      added
    else
      raise ArgumentError,
        "builder sink must be a Document or Element, got #{@sink.class}"
    end
  end

  private

  def write_attributes(attributes)
    case attributes
    when Hash
      attributes.each do |k, v|
        @buf << " " << k.to_s << '="' << escape_attr(v) << '"'
      end
    when nil then # nothing
    else
      raise ArgumentError,
        "attributes must be a Hash, got #{attributes.class}"
    end
  end

  def escape_text(value)
    value.gsub(ESCAPE_RE, ESCAPE)
  end

  def escape_attr(value)
    value.to_s.gsub(ESCAPE_RE, ESCAPE)
  end
end
