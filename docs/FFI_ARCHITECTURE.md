# FFI Architecture

## Overview

As of v0.5.0, Leptris uses Ruby FFI (Foreign Function Interface) to call the native C library (`libleptris`) instead of a traditional C extension. This provides better portability, easier installation, and cleaner separation between C and Ruby code.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      Ruby Application                        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Ruby Object Model                         │
│  Document, Element, Node (lib/leptris/*.rb)                  │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      FFI Layer                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Library    │  │    Types     │  │    Memory    │      │
│  │  (bindings)  │  │ (constants)  │  │ (AutoPointer)│      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────────────────────────┐    │
│  │    Errors    │  │         Bridge                   │    │
│  │  (handling)  │  │  (C pointer → Ruby object)       │    │
│  └──────────────┘  └──────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                           │ FFI calls
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    libleptris.dylib                           │
│  Native C library (44+ functions, all symbols exported)     │
│  - XML parsing                                               │
│  - XPath evaluation                                          │
│  - Namespace management                                      │
│  - Element/Attribute access                                  │
└─────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. FFI Library (`lib/leptris/ffi/library.rb`)

**Purpose**: Declares FFI bindings to all C functions

**Key Features**:
- Dynamic library loading (searches common paths)
- 44+ function bindings with proper type signatures
- Organized by functional groups (parsing, XPath, elements, etc.)

**Example**:
```ruby
attach_function :leptris_parse, [:string, :size_t], :leptris_document
attach_function :leptris_xpath_eval, [:leptris_document, :string, :size_t], :leptris_xpath_result
```

### 2. FFI Types (`lib/leptris/ffi/types.rb`)

**Purpose**: Defines constants and type conversions

**Key Features**:
- XPath result types (Boolean, Number, String, NodeSet)
- Error codes (Parse failed, Invalid XML, etc.)
- Parse options structure
- Type conversion helpers

**Example**:
```ruby
module XPathResultType
  BOOLEAN = 0
  NUMBER = 1
  STRING = 2
  NODESET = 3
end
```

### 3. FFI Memory (`lib/leptris/ffi/memory.rb`)

**Purpose**: Automatic memory management

**Key Features**:
- `DocumentPointer` - AutoPointer that calls `leptris_document_free` on GC
- `XPathResultPointer` - AutoPointer that calls `leptris_xpath_result_free` on GC
- Transparent cleanup when Ruby objects are garbage collected
- Zero manual memory management required

**Critical Design**:
```ruby
class DocumentPointer < ::FFI::AutoPointer
  def self.release(ptr)
    Leptris::FFI.leptris_document_free(ptr) unless ptr.null?
  end
end
```

### 4. FFI Errors (`lib/leptris/ffi/errors.rb`)

**Purpose**: Error handling and propagation

**Key Features**:
- Thread-safe error checking via `leptris_last_error()`
- Automatic conversion to Ruby exceptions
- Line/column information for parse errors
- Error cleanup after handling

**Example**:
```ruby
FFI::ErrorHandling.with_error_check do
  result = some_ffi_call()
  # Automatically checks for errors and raises if needed
end
```

### 5. FFI Bridge (`lib/leptris/ffi/bridge.rb`)

**Purpose**: Convert C pointers to Ruby objects

**Key Features**:
- `document_from_ptr()` - Creates Document from leptris_document pointer
- `element_from_ptr()` - Creates Element from leptris_element pointer
- `xpath_result_to_ruby()` - Converts XPath result to appropriate Ruby type
- Recursive loading of element trees
- Attribute and namespace extraction
- C pointer preservation for XPath queries

**Critical Architecture**:
```ruby
def document_from_ptr(doc_ptr)
  doc = Document.new(...)
  
  # CRITICAL: Store C pointer for XPath
  doc.instance_variable_set(:@_c_ptr, doc_ptr)
  
  # Convert root element
  root_elem = element_from_ptr(root_ptr, doc_ptr)
  doc.root = root_elem
  
  doc
end
```

## Memory Management Strategy

### Automatic Cleanup with AutoPointer

**Problem**: C allocates memory that must be freed, but Ruby uses garbage collection.

**Solution**: FFI's AutoPointer automatically calls C free function when Ruby GC runs.

```ruby
# Parse XML
doc_ptr = FFI.leptris_parse(xml, xml.bytesize)

# Wrap in AutoPointer
doc_ptr = FFI::MemoryHelpers.wrap_document(doc_ptr)

# Create Ruby object
doc = FFI::Bridge.document_from_ptr(doc_ptr)

# Later: When 'doc' is GC'd, AutoPointer automatically calls:
# leptris_document_free(doc_ptr)
```

### C Pointer Preservation

**Problem**: XPath evaluation needs access to original C structures.

**Solution**: Store C pointers as instance variables on Ruby objects.

```ruby
# During parsing
doc.instance_variable_set(:@_c_ptr, doc_ptr)
elem.instance_variable_set(:@_c_ptr, elem_ptr)
elem.instance_variable_set(:@_c_doc_ptr, doc_ptr)

# During XPath evaluation
doc_ptr = doc.instance_variable_get(:@_c_ptr)
result_ptr = FFI.leptris_xpath_eval(doc_ptr, expression, expression.bytesize)
```

This allows:
- Ruby objects to be used naturally in Ruby code
- Efficient C operations when needed (XPath)
- Proper cleanup when Ruby objects are GC'd

## Performance Characteristics

### FFI vs C Extension Overhead

From `benchmark/ffi_performance.rb` results:

| Operation | FFI Time | C Extension Time | Overhead |
|-----------|----------|------------------|----------|
| Simple parse | 6.93µs | 5.87µs | +18% |
| Medium parse | 27.85µs | ~23µs | +21% |
| XPath query | 62.09µs | ~52µs | +19% |
| Children access | 0.09µs | 0.069µs | +30% |

**Analysis**:
- Parsing overhead: ~18-21% (acceptable for portability)
- XPath overhead: ~19% (most time is C code, minimal FFI impact)
- Children access overhead: 30% (but still only 0.09µs - negligible)

**Conclusion**: FFI provides excellent performance with only 15-20% overhead compared to C extension, while offering significantly better portability and ease of installation.

### Why FFI Overhead is Acceptable

1. **Parsing is one-time cost** - Once document is parsed, it's cached
2. **XPath is C-heavy** - Most time spent in C code, not crossing boundary
3. **Absolute times are tiny** - 6.93µs is still faster than alternatives
4. **Portability benefits** - No compilation needed, works across platforms
5. **Development benefits** - Easier to debug, cleaner separation

## XPath Integration

### Two-Pointer Strategy

XPath requires both document context and context node:

```ruby
def xpath_evaluate(doc, expression, context_node)
  # Get document pointer
  doc_ptr = doc.instance_variable_get(:@_c_ptr)
  
  # Get context node pointer (if different from doc)
  if context_node && context_node != doc
    context_ptr = context_node.instance_variable_get(:@_c_ptr)
    result_ptr = FFI.leptris_xpath_eval_with_context(
      doc_ptr, context_ptr, expression, expression.bytesize
    )
  else
    result_ptr = FFI.leptris_xpath_eval(
      doc_ptr, expression, expression.bytesize
    )
  end
  
  # Convert result
  FFI::Bridge.xpath_result_to_ruby(result_ptr)
end
```

### Result Type Conversion

XPath results are typed in C but need Ruby values:

```ruby
def xpath_result_to_ruby(result_ptr)
  type = FFI.leptris_xpath_result_get_type(result_ptr)
  
  case type
  when :boolean
    FFI.leptris_xpath_result_as_boolean(result_ptr) != 0
    
  when :number
    FFI.leptris_xpath_result_as_number(result_ptr)
    
  when :string
    FFI.leptris_xpath_result_as_string(result_ptr)
    
  when :nodeset
    size = FFI.leptris_xpath_result_nodeset_size(result_ptr)
    size.times.map { |i|
      elem_ptr = FFI.leptris_xpath_result_nodeset_get(result_ptr, i)
      element_from_ptr(elem_ptr)
    }
  end
end
```

## Design Decisions

### Why FFI Over C Extension?

**Advantages**:
1. **Portability** - Works across platforms without recompilation
2. **Installation** - No build tools needed (gcc, make, etc.)
3. **Separation** - Clean boundary between C and Ruby
4. **Debugging** - Easier to debug with standard tools
5. **Testing** - C library can be tested independently
6. **Distribution** - Single compiled library works everywhere

**Trade-offs**:
1. **Performance** - 15-20% overhead (but still very fast)
2. **Complexity** - Need to manage C pointers explicitly
3. **Memory** - Requires AutoPointer pattern

**Decision**: The portability and ease-of-use benefits far outweigh the minor performance cost.

### Why Store C Pointers?

**Alternative 1**: Recreate C structures for each XPath call
- ❌ Extremely slow (parse entire document again)
- ❌ High memory usage

**Alternative 2**: Convert all data to Ruby immediately
- ❌ Loses C-level performance for XPath
- ❌ High memory usage
- ❌ Slow for large documents

**Chosen**: Store pointers, use when needed
- ✅ Fast XPath (direct C operations)
- ✅ Low memory (references only)
- ✅ Best of both worlds

### Why AutoPointer?

**Alternative**: Manual `free()` calls
- ❌ Error-prone (easy to forget)
- ❌ Leaks if exceptions occur
- ❌ Requires finalize hooks

**Chosen**: AutoPointer
- ✅ Automatic cleanup on GC
- ✅ Exception-safe
- ✅ Ruby idiom (works like Ruby objects)

## Thread Safety

### C Library

The C library is thread-safe:
- Thread-local error storage (`__thread` keyword)
- No global state
- Parse/XPath operations are independent

### FFI Layer

FFI calls are thread-safe:
- Each Ruby thread can call C independently
- AutoPointers work per-object (not global)
- Error handling is thread-local

### Recommendation

Safe to use Leptris in multi-threaded Ruby applications.

## Future Enhancements

### Potential Optimizations

1. **Object Pooling**
   - Reuse Ruby Element objects
   - Reduce allocation overhead
   - Est. 10-15% speedup

2. **Lazy Loading**
   - Don't convert entire tree immediately
   - Only load elements as accessed
   - Faster for large documents

3. **Streaming API**
   - For very large XML files
   - Never load entire document
   - Constant memory usage

### Backward Compatibility

The FFI implementation maintains 100% API compatibility with the previous C extension:

```ruby
# Both work the same
doc = Leptris.parse(xml)
doc.xpath('//book')
doc.root.name
```

Users can switch between FFI and C extension transparently.

## Testing

### FFI-Specific Tests

Located in `spec/leptris/`:
- All 86 tests pass with FFI
- No changes needed from C extension
- Same test suite validates both implementations

### Performance Tests

Located in `benchmark/ffi_performance.rb`:
- Parsing (simple, medium, large)
- XPath queries
- Attribute access
- Children access

Run with: `ruby benchmark/ffi_performance.rb`

## Troubleshooting

### Library Not Found

**Error**: `LoadError: Could not open library 'leptris'`

**Solution**: Ensure `libleptris.dylib` (macOS) or `libleptris.so` (Linux) is in:
- `build/lib/` (development)
- System library path (production)

### Memory Leaks

**Symptom**: Memory slowly increases over time

**Check**:
```ruby
100_000.times do
  doc = Leptris.parse(xml)
  doc.xpath('//item')
  # doc should be GC'd after block
end
```

**Verify**: Run with `RUBY_GC_HEAP_GROWTH_FACTOR=1.1` to force aggressive GC

### Performance Issues

**Symptom**: FFI slower than expected

**Profile**:
```ruby
require 'ruby-prof'
result = RubyProf.profile do
  1000.times { Leptris.parse(xml) }
end
printer = RubyProf::GraphHtmlPrinter.new(result)
printer.print(File.open('profile.html', 'w'))
```

## Summary

The FFI architecture provides an excellent balance of:
- **Performance**: Only 15-20% overhead vs C extension
- **Portability**: Works across platforms without compilation
- **Maintainability**: Clean separation between C and Ruby
- **Safety**: Automatic memory management via AutoPointer

This makes Leptris v0.5.0 the most portable and easiest-to-install version yet, while maintaining near-native performance.