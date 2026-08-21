# Future Vision: Leptris Beyond v0.4.0

**Created**: 2025-01-29
**Status**: Planning Document
**Context**: Long-term vision from TODO.libleptris.md

## Overview

This document captures the long-term architectural vision for Leptris, including transformation into libleptris (a reusable C library) and enhanced features. This represents work beyond v0.4.0 and likely v0.5.0+.

## Vision: libleptris - Reusable C Library

### Goal

Refactor Leptris into **libleptris**, a standalone C library that can be:
- Linked into other C/C++ projects
- Used by the Leptris CLI (written in C)
- Wrapped by the Ruby gem (leptris)
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
│          libleptris.so                   │
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
│  │  leptris  │  │  Custom  │            │
│  │  CLI     │  │  Tools   │            │
│  └──────────┘  └──────────┘            │
└─────────────────────────────────────────┘
```

### Components

#### 1. libleptris (Core C Library)
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
leptris_document_t* leptris_parse_string(const char* xml, size_t len, leptris_options_t* opts);
leptris_document_t* leptris_parse_file(const char* filename, leptris_options_t* opts);

// XPath evaluation
leptris_nodeset_t* leptris_xpath_eval(leptris_document_t* doc, const char* expr);

// Pretty printing
char* leptris_format_xml(leptris_document_t* doc, leptris_format_options_t* opts);

// Memory management
void leptris_document_free(leptris_document_t* doc);
void leptris_nodeset_free(leptris_nodeset_t* nodeset);
```

#### 2. Leptris CLI (C Application)
- **Standalone binary** linking libleptris
- **xmllint-compatible** commands and options
- **Fast startup** (C binary, no Ruby overhead)
- **Shell-friendly** with proper exit codes

**Commands** (inspired by xmllint):
```bash
# XPath queries
leptris --xpath "//book[@price > 20]" document.xml

# Pretty printing
leptris --format --indent 2 document.xml
leptris --format --compact document.xml

# Validation
leptris --validate document.xml

# Schema validation (future)
leptris --schema schema.xsd document.xml

# Debugging
leptris --debug --xpath "//item" document.xml
leptris --timing document.xml
```

#### 3. Ruby Gem (High-Level Interface)
- **Thin wrapper** around libleptris
- **Ruby-friendly** API with blocks and iterators
- **Current API preserved** for backward

 compatibility
- **Performance** close to direct C usage

**Implementation**:
```ruby
# Current approach (stays the same externally)
doc = Leptris.parse(xml)
results = doc.xpath('//book')

# Internally backed by libleptris C library
```

### Parsing Modes

#### SAX (Event-Driven)
- **Memory efficient**: Stream processing
- **Fast**: No DOM construction
- **Use case**: Large documents, extraction

```c
leptris_sax_parse(xml, &callbacks, user_data);
```

#### StAX (Pull Parsing)
- **Control**: Application pulls events
- **Flexible**: Skip unwanted sections
- **Use case**: Selective parsing

```c
leptris_reader_t* reader = leptris_reader_new(xml);
while (leptris_reader_read(reader)) {
    // Process events
}
```

#### DOM (Tree Construction)
- **Convenient**: Full tree in memory
- **XPath**: Enables complex queries
- **Use case**: Current Leptris behavior

```c
leptris_document_t* doc = leptris_parse_string(xml, len, NULL);
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
} leptris_format_options_t;
```

## Implementation Roadmap

### Phase 1: API Stabilization (v0.4.0-v0.5.0)
- Complete current Ruby API
- Ensure comprehensive test coverage
- Document all behaviors
- Establish API contracts

### Phase 2: C API Design (v0.6.0)
- Design libleptris C API
- Create header files
- Document API conventions
- Plan memory management

### Phase 3: Refactoring (v0.7.0)
- Extract C code into libleptris
- Maintain Ruby bindings
- Separate concerns cleanly
- Add C unit tests

### Phase 4: Multi-Mode Parsing (v0.8.0)
- Implement SAX parsing
- Implement StAX parsing
- Keep DOM mode (current)
- Add mode selection API

### Phase 5: CLI Implementation (v0.9.0)
- Build C CLI using libleptris
- Implement xmllint-compatible commands
- Add leptris-specific features
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

### For Leptris Users
- **Faster CLI**: C binary startup
- **More Modes**: SAX/StAX options
- **Better Tools**: Enhanced CLI features
- **Same API**: Backward compatible

## Migration Path

1. **v0.4.0**: Complete documentation
2. **v0.5.0**: Namespace prefixes, API finalization
3. **v0.6.0**: Design and prototype libleptris API
4. **v0.7.0**: Refactor to libleptris + Ruby bindings
5. **v0.8.0**: Add SAX/StAX modes
6. **v0.9.0**: C CLI + pretty printing
7. **v1.0.0**: Stable libleptris release

## Timeline

- **Near-term (2025)**: v0.4.0-v0.5.0 (Ruby focus)
- **Mid-term (2026)**: v0.6.0-v0.8.0 (libleptris extraction)
- **Long-term (2027+)**: v0.9.0-v1.0.0 (Multi-language, stable)

## Conclusion

This vision transforms Leptris from a Ruby gem into a universal XML processing library usable from any language. The core libleptris library would provide fast, reliable XML processing while maintaining backward compatibility with the current Ruby API.

**Key Principle**: Evolution, not revolution. Each step maintains compatibility while adding new capabilities.

**Next Review**: After v0.5.0 completion (2025 Q2)