# Future Vision: Taurus Beyond v0.4.0

**Created**: 2025-01-29
**Status**: Planning Document
**Context**: Long-term vision from TODO.libtaurus.md

## Overview

This document captures the long-term architectural vision for Taurus, including transformation into libtaurus (a reusable C library) and enhanced features. This represents work beyond v0.4.0 and likely v0.5.0+.

## Vision: libtaurus - Reusable C Library

### Goal

Refactor Taurus into **libtaurus**, a standalone C library that can be:
- Linked into other C/C++ projects
- Used by the Taurus CLI (written in C)
- Wrapped by the Ruby gem (taurus)
- Integrated into any language with C FFI

### Architecture

```
┌─────────────────────────────────────────┐
│         Language Bindings               │
│  ┌──────────┐  ┌──────────┐  ┌────────┐│
│  │  Ruby    │  │  Python  │  │  Node  ││
│  │  Gem     │  │  Package │  │  Module││
│  └──────────┘  └──────────┘  └────────┘│
└─────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│          libtaurus.so                   │
│     (Core  C Library + API)              │
│  ┌─────────────────────────────────────┐│
│  │ XML Parser (SAX/StAX/DOM)           ││
│  │ XPath 1.0 Engine                    ││
│  │ XML Namespaces 1.0                  ││
│  │ Pretty Printing                     ││
│  │ Memory Management                   ││
│  └─────────────────────────────────────┘│
└─────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│          CLI Applications               │
│  ┌──────────┐  ┌──────────┐            │
│  │  taurus  │  │  Custom  │            │
│  │  CLI     │  │  Tools   │            │
│  └──────────┘  └──────────┘            │
└─────────────────────────────────────────┘
```

### Components

#### 1. libtaurus (Core C Library)
- **Pure C implementation** with clean API
- **Zero dependencies** (no libxml2)
- **Thread-safe** operations
- **Memory efficient** with configurable allocators
- **Cross-platform** (Linux, macOS, Windows, BSD)
- **CMake build system**

**Features**:
- XML parsing (SAX, StAX, DOM modes)
- XPath 1.0 evaluation
- XML Namespaces 1.0
- XML pretty-printing
- Error handling with detailed messages
- Memory management with custom allocators

**API Design**:
```c
// Core parsing
taurus_document_t* taurus_parse_string(const char* xml, size_t len, taurus_options_t* opts);
taurus_document_t* taurus_parse_file(const char* filename, taurus_options_t* opts);

// XPath evaluation
taurus_nodeset_t* taurus_xpath_eval(taurus_document_t* doc, const char* expr);

// Pretty printing
char* taurus_format_xml(taurus_document_t* doc, taurus_format_options_t* opts);

// Memory management
void taurus_document_free(taurus_document_t* doc);
void taurus_nodeset_free(taurus_nodeset_t* nodeset);
```

#### 2. Taurus CLI (C Application)
- **Standalone binary** linking libtaurus
- **xmllint-compatible** commands and options
- **Fast startup** (C binary, no Ruby overhead)
- **Shell-friendly** with proper exit codes

**Commands** (inspired by xmllint):
```bash
# XPath queries
taurus --xpath "//book[@price > 20]" document.xml

# Pretty printing
taurus --format --indent 2 document.xml
taurus --format --compact document.xml

# Validation
taurus --validate document.xml

# Schema validation (future)
taurus --schema schema.xsd document.xml

# Debugging
taurus --debug --xpath "//item" document.xml
taurus --timing document.xml
```

#### 3. Ruby Gem (High-Level Interface)
- **Thin wrapper** around libtaurus
- **Ruby-friendly** API with blocks and iterators
- **Current API preserved** for backward

 compatibility
- **Performance** close to direct C usage

**Implementation**:
```ruby
# Current approach (stays the same externally)
doc = Taurus.parse(xml)
results = doc.xpath('//book')

# Internally backed by libtaurus C library
```

### Parsing Modes

#### SAX (Event-Driven)
- **Memory efficient**: Stream processing
- **Fast**: No DOM construction
- **Use case**: Large documents, extraction

```c
taurus_sax_parse(xml, &callbacks, user_data);
```

#### StAX (Pull Parsing)
- **Control**: Application pulls events
- **Flexible**: Skip unwanted sections
- **Use case**: Selective parsing

```c
taurus_reader_t* reader = taurus_reader_new(xml);
while (taurus_reader_read(reader)) {
    // Process events
}
```

#### DOM (Tree Construction)
- **Convenient**: Full tree in memory
- **XPath**: Enables complex queries
- **Use case**: Current Taurus behavior

```c
taurus_document_t* doc = taurus_parse_string(xml, len, NULL);
```

### XML Pretty Printing

**Features**:
- Configurable indentation (spaces/tabs)
- Line wrapping at specified column
- Attribute formatting (inline/separate lines)
- Whitespace normalization
- Compact mode (remove all whitespace)

**Options**:
```c
typedef struct {
    int indent_size;        // 2, 4, etc.
    bool use_tabs;          // tabs vs spaces
    int wrap_column;        // 80, 120, etc.
    bool compact;           // remove whitespace
    bool sort_attributes;   // alphabetical
} taurus_format_options_t;
```

## Implementation Roadmap

### Phase 1: API Stabilization (v0.4.0-v0.5.0)
- Complete current Ruby API
- Ensure comprehensive test coverage
- Document all behaviors
- Establish API contracts

### Phase 2: C API Design (v0.6.0)
- Design libtaurus C API
- Create header files
- Document API conventions
- Plan memory management

### Phase 3: Refactoring (v0.7.0)
- Extract C code into libtaurus
- Maintain Ruby bindings
- Separate concerns cleanly
- Add C unit tests

### Phase 4: Multi-Mode Parsing (v0.8.0)
- Implement SAX parsing
- Implement StAX parsing
- Keep DOM mode (current)
- Add mode selection API

### Phase 5: CLI Implementation (v0.9.0)
- Build C CLI using libtaurus
- Implement xmllint-compatible commands
- Add taurus-specific features
- Document CLI usage

### Phase 6: Pretty Printing (v0.9.0)
- Implement formatting engine
- Add configuration options
- Support various styles
- Integrate with CLI

### Phase 7: CMake Build (v0.10.0)
- Create CMake build system
- Support cross-compilation
- Generate pkg-config files
- Build shared/static libraries

### Phase 8: Language Bindings (v1.0.0+)
- Python bindings
- Node.js bindings
- Other language bindings
- Consistent API across languages

## Technical Considerations

### Memory Management
- **Allocator API**: Allow custom allocators
- **Reference Counting**: For shared resources
- **Pool Allocators**: For high-frequency allocations
- **Leak Detection**: Built-in debugging support

### Thread Safety
- **Immutable Documents**: Safe to share
- **Context Isolation**: Per-thread contexts
- **Lock-Free Reads**: Where possible
- **Documented Guarantees**: Clear thread-safety docs

### Error Handling
- **Error Codes**: Standard C approach
- **Error Context**: Detailed error information
- **Recovery**: Graceful error handling
- **Logging**: Configurable logging levels

### Performance
- **Zero-Copy**: Where possible
- **SIMD**: Continue optimizations
- **Memory Pools**: Reduce allocations
- **Lazy Evaluation**: Defer expensive operations

## Benefits

### For C/C++ Projects
- **Direct Integration**: No Ruby dependency
- **Fast Performance**: Native C speed
- **Small Footprint**: Minimal binary size
- **Standard API**: Familiar C patterns

### For Other Languages
- **Easy Bindings**: Standard C FFI
- **Consistent Behavior**: Same core library
- **Native Performance**: No interpretation overhead
- **Wide Compatibility**: Works everywhere

### For Taurus Users
- **Faster CLI**: C binary startup
- **More Modes**: SAX/StAX options
- **Better Tools**: Enhanced CLI features
- **Same API**: Backward compatible

## Migration Path

1. **v0.4.0**: Complete documentation
2. **v0.5.0**: Namespace prefixes, API finalization
3. **v0.6.0**: Design and prototype libtaurus API
4. **v0.7.0**: Refactor to libtaurus + Ruby bindings
5. **v0.8.0**: Add SAX/StAX modes
6. **v0.9.0**: C CLI + pretty printing
7. **v1.0.0**: Stable libtaurus release

## Timeline

- **Near-term (2025)**: v0.4.0-v0.5.0 (Ruby focus)
- **Mid-term (2026)**: v0.6.0-v0.8.0 (libtaurus extraction)
- **Long-term (2027+)**: v0.9.0-v1.0.0 (Multi-language, stable)

## Conclusion

This vision transforms Taurus from a Ruby gem into a universal XML processing library usable from any language. The core libtaurus library would provide fast, reliable XML processing while maintaining backward compatibility with the current Ruby API.

**Key Principle**: Evolution, not revolution. Each step maintains compatibility while adding new capabilities.

**Next Review**: After v0.5.0 completion (2025 Q2)