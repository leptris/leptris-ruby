# TODO 4 — SAX parser wrapper

## Goal

Wrap libleptris's C SAX parser (`leptris_sax_parse`, `leptris_sax_parser_feed`)
behind a Nokogiri-compatible Ruby SAX API.

## Nokogiri SAX API (target)

```ruby
class MyHandler < Nokogiri::XML::SAX::Document
  def start_document; end
  def end_document; end
  def start_element(name, attrs = []); end
  def end_element(name); end
  def characters(string); end
  def comment(string); end
  def cdata_block(string); end
  def processing_instruction(name, content); end
  def warning(msg); end
  def error(msg); end
end

parser = Nokogiri::XML::SAX::Parser.new(MyHandler.new)
parser.parse(File.read('file.xml'))
# or streaming:
parser.parse(io)  # reads in chunks
```

## Leptris SAX API (source)

From `src/include/leptris/sax/sax.h`:

```c
struct LeptrisSAXHandler {
  void (*start_document)(void* user_data);
  void (*end_document)(void* user_data);
  void (*start_element)(void* user_data, const char* name, const char** attrs);
  void (*end_element)(void* user_data, const char* name);
  void (*characters)(void* user_data, const char* text, size_t len);
  void (*comment)(void* user_data, const char* comment);
  void (*cdata)(void* user_data, const char* cdata);
  void (*processing_instruction)(void* user_data, const char* target, const char* data);
  void (*start_prefix_mapping)(void* user_data, const char* prefix, const char* uri);
  void (*end_prefix_mapping)(void* user_data, const char* prefix);
  void (*error)(void* user_data, const char* message, int line, int column);
};

int leptris_sax_parse(const char* xml, size_t len,
                     LeptrisSAXHandler* handler, void* user_data);
LeptrisSAXParser* leptris_sax_parser_create(LeptrisSAXHandler* handler, void* user_data);
int leptris_sax_parser_feed(LeptrisSAXParser* parser, const char* xml,
                           size_t len, int is_final);
void leptris_sax_parser_free(LeptrisSAXParser* parser);
```

## Implementation

```ruby
module Leptris
  module XML
    module SAX
      class Document
        def start_document; end
        def end_document; end
        def start_element(name, attrs = []); end
        def end_element(name); end
        def characters(string); end
        def comment(string); end
        def cdata(string); end
        def processing_instruction(name, content); end
        def start_prefix_mapping(prefix, uri); end
        def end_prefix_mapping(prefix); end
        def error(message, line, column); end
        def warning(message); end
      end

      class Parser
        def initialize(handler = Document.new)
          @handler = handler
        end

        def parse(io_or_string)
          xml = io_or_string.respond_to?(:read) ? io_or_string.read : io_or_string

          handler_struct = build_handler_struct(@handler)
          rc = FFI.leptris_sax_parse(xml, xml.bytesize, handler_struct, nil)
          raise ParseError, "SAX parse failed (rc=#{rc})" if rc != 0
          self
        end

        private

        def build_handler_struct(handler)
          s = FFI::SAXHandler.new
          s[:start_document]    = make_callback(:start_document)
          s[:end_document]      = make_callback(:end_document)
          s[:start_element]     = make_callback(:start_element)
          s[:end_element]       = make_callback(:end_element)
          s[:characters]        = make_callback(:characters)
          s[:comment]           = make_callback(:comment)
          s[:cdata]             = make_callback(:cdata)
          s[:processing_instruction] = make_callback(:processing_instruction)
          s[:start_prefix_mapping]   = make_callback(:start_prefix_mapping)
          s[:end_prefix_mapping]     = make_callback(:end_prefix_mapping)
          s[:error]             = make_callback(:error)
          s
        end

        def make_callback(event)
          ::FFI::Function.new(:void, [:pointer]) do |_user_data|
            @handler.send(event)
          end
        end
      end
    end
  end
end
```

## Callback signatures (FFI::Function)

Each callback needs the right C signature:

```ruby
# start_document: void(void*)
s[:start_document] = FFI::Function.new(:void, [:pointer]) do
  @handler.start_document
end

# start_element: void(void*, const char*, const char**)
# attrs is a NULL-terminated array of name-value pairs
s[:start_element] = FFI::Function.new(:void, [:pointer, :string, :pointer]) do |_, name, attrs_ptr|
  attrs = []
  unless attrs_ptr.null?
    offset = 0
    loop do
      key_ptr = attrs_ptr.get_pointer(offset)
      break if key_ptr.null?
      val_ptr = attrs_ptr.get_pointer(offset + FFI.type_size(:pointer))
      break if val_ptr.null?
      attrs << key_ptr.read_string
      attrs << val_ptr.read_string
      offset += 2 * FFI.type_size(:pointer)
    end
  end
  @handler.start_element(name, attrs.each_slice(2).to_h)
end

# characters: void(void*, const char*, size_t)
s[:characters] = FFI::Function.new(:void, [:pointer, :pointer, :size_t]) do |_, text_ptr, len|
  @handler.characters(text_ptr.read_bytes(len).force_encoding('UTF-8'))
end

# error: void(void*, const char*, int, int)
s[:error] = FFI::Function.new(:void, [:pointer, :string, :int, :int]) do |_, msg, line, col|
  @handler.error(msg, line, col)
end
```

## Streaming (incremental) parsing

For large documents, use `leptris_sax_parser_create` + `feed`:

```ruby
def parse(io)
  return parse(io.read) unless io.respond_to?(:read)

  handler_struct = build_handler_struct(@handler)
  parser = FFI.leptris_sax_parser_create(handler_struct, nil)

  io.each_chunk(4096) do |chunk|
    rc = FFI.leptris_sax_parser_feed(parser, chunk, chunk.bytesize, 0)
    break if rc != 0
  end
  # Final flush
  FFI.leptris_sax_parser_feed(parser, '', 0, 1)
ensure
  FFI.leptris_sax_parser_free(parser) if parser
end
```

## File

```
lib/leptris/xml/sax.rb
lib/leptris/xml/sax/parser.rb
lib/leptris/xml/sax/document.rb
```

## Autoload

```ruby
# lib/leptris/xml/sax.rb
module Leptris
  module XML
    module SAX
      autoload :Parser,  'leptris/xml/sax/parser'
      autoload :Document, 'leptris/xml/sax/document'
    end
  end
end
```
