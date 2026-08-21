# Leptris Error Message Catalog

This document provides a comprehensive reference for all error types, codes, causes, and solutions in Leptris.

## Error Types Overview

Leptris provides three main error types:

| Error Type | Purpose | Common Codes |
|------------|---------|--------------|
| `Leptris::ParseError` | XML parsing failures | `:parse_failed`, `:unclosed_tag`, `:empty_input` |
| `Leptris::XPathError` | XPath syntax and evaluation errors | `:xpath_syntax`, `:xpath_function` |
| `Leptris::EvaluationError` | Runtime evaluation issues | `:xpath_evaluation`, `:xpath_type_error` |

All errors inherit from `StandardError` and provide comprehensive diagnostic information.

## Parse Errors

### EMPTY_INPUT

**Code**: `:empty_input`

**Cause**: Empty string passed to `Leptris.parse()`

**Example**:
```ruby
Leptris.parse('')
# => Leptris::ParseError: Empty input provided
#    code: :empty_input
```

**Solution**: Provide valid XML content. Check your data source before parsing.

**Common Scenarios**:
- Reading from empty file
- Network request returned empty body
- User input was blank

---

### NULL_INPUT

**Code**: `:null_input`

**Cause**: NULL (nil) value passed to parser

**Example**:
```ruby
Leptris.parse(nil)
# => Leptris::ParseError: NULL input provided
#    code: :null_input
```

**Solution**: Ensure input is a valid string. Add nil checks before parsing.

```ruby
# Good practice
xml = fetch_xml_data()
doc = Leptris.parse(xml) if xml && !xml.empty?
```

---

### PARSE_FAILED

**Code**: `:parse_failed`

**Cause**: Malformed XML structure

**Examples**:
```ruby
# Missing closing bracket
Leptris.parse('<root')
# => ParseError: Expected '>' at line 1, column 6

# Invalid tag name
Leptris.parse('<123invalid>')
# => ParseError: Invalid tag name at line 1, column 2

# Malformed attribute
Leptris.parse('<root attr=value>')
# => ParseError: Expected quoted attribute value
```

**Solution**: Validate XML syntax. Use XML schema validation if available.

**Common Issues**:
- Missing `>` or `<` characters
- Invalid characters in tag names
- Unquoted attribute values
- Incorrectly nested elements

**Related Documentation**: [XML 1.0 Specification](https://www.w3.org/TR/xml/)

---

### UNCLOSED_TAG

**Code**: `:unclosed_tag`

**Cause**: XML element not properly closed

**Examples**:
```ruby
# Missing closing tag
Leptris.parse('<root><item></root>')
# => ParseError: Unclosed tag 'item' at line 1, column 7
#    Context:
#      <root><item></root>
#            ^

# Mismatched tags
Leptris.parse('<root><item></items></root>')
# => ParseError: Mismatched closing tag at line 1, column 13
```

**Solution**: Ensure all opening tags have matching closing tags.

**Best Practices**:
- Use self-closing tags where appropriate: `<item/>`
- Maintain proper nesting hierarchy
- Use XML validators during development

---

## XPath Errors

### XPATH_SYNTAX

**Code**: `:xpath_syntax`

**Cause**: Invalid XPath expression syntax

**Examples**:

**Unclosed Predicate**:
```ruby
doc.xpath('//item[')
# => XPathError: Unexpected token in primary expression: EOF
#    Line: 1, Column: 8
#    Context:
#      //item[
#             ^
```

**Missing Attribute Name**:
```ruby
doc.xpath('//item/@')
# => XPathError: Expected attribute name after '@'
#    Line: 1, Column: 9
```

**Invalid Function Syntax**:
```ruby
doc.xpath('count(//item')
# => XPathError: Unclosed function call
#    Line: 1, Column: 14
```

**Solution**: Check XPath syntax against XPath 1.0 specification.

**Common Mistakes**:
- Forgetting to close brackets `[...]`
- Missing parentheses in function calls
- Invalid operator usage
- Incomplete attribute references

**Related Documentation**: [XPath 1.0 Specification](https://www.w3.org/TR/xpath/)

---

### XPATH_FUNCTION

**Code**: `:xpath_function`

**Cause**: Unknown function name or invalid function arguments

**Examples**:

**Unknown Function**:
```ruby
doc.xpath('unknown_func()')
# => XPathError: Unknown function 'unknown_func' at line 1, column 1
#    Suggestion: Did you mean count(), concat(), or contains()?
```

**Wrong Number of Arguments**:
```ruby
doc.xpath('concat("a")')
# => XPathError: Function 'concat' requires at least 2 arguments, got 1
#    Line: 1, Column: 1

doc.xpath('ceiling(1, 2)')
# => XPathError: Function 'ceiling' accepts 1 argument, got 2
```

**Solution**: Use only XPath 1.0 standard functions with correct arguments.

**XPath 1.0 Functions** (all 27 supported):

**String Functions**:
- `string(object?)` - Convert to string
- `concat(string, string, ...)` - Concatenate (2+ args)
- `starts-with(string, string)` - Prefix test
- `contains(string, string)` - Substring test
- `substring(string, number, number?)` - Extract substring
- `string-length(string?)` - String length
- `normalize-space(string?)` - Normalize whitespace
- `translate(string, string, string)` - Character translation
- `substring-before(string, string)` - Before delimiter
- `substring-after(string, string)` - After delimiter

**Boolean Functions**:
- `boolean(object)` - Convert to boolean
- `not(boolean)` - Logical NOT
- `true()` - Boolean true
- `false()` - Boolean false
- `lang(string)` - Language matching

**Number Functions**:
- `number(object?)` - Convert to number
- `sum(node-set)` - Sum node values
- `floor(number)` - Round down
- `ceiling(number)` - Round up
- `round(number)` - Round to nearest

**Node-set Functions**:
- `count(node-set)` - Count nodes
- `id(object)` - Select by ID
- `last()` - Context size
- `position()` - Context position (1-based)
- `local-name(node-set?)` - Local name
- `namespace-uri(node-set?)` - Namespace URI
- `name(node-set?)` - Qualified name

---

### XPATH_EVALUATION

**Code**: `:xpath_evaluation`

**Cause**: Runtime evaluation error (not a syntax error)

**Examples**:

**Type Conversion Error**:
```ruby
doc.xpath('count("not-a-nodeset")')
# => XPathError: Function 'count' requires node-set argument
```

**Division by Zero**:
```ruby
doc.xpath('1 div 0')
# => XPathError: Division by zero in arithmetic expression
```

**Solution**: Ensure operands are correct types and operations are valid.

**Common Runtime Errors**:
- Type mismatches in function arguments
- Invalid arithmetic operations
- NULL reference errors
- Out-of-range numeric operations

---

## Error Attributes Reference

All error objects provide these attributes:

### message
**Type**: String
**Description**: Human-readable error description

Example:
```ruby
rescue Leptris::ParseError => e
  puts e.message
  # => "Failed to parse root element at line 1, column 1"
end
```

### code
**Type**: Symbol
**Description**: Machine-readable error code

Example:
```ruby
rescue Leptris::XPathError => e
  case e.code
  when :xpath_syntax
    # Handle syntax errors
  when :xpath_function
    # Handle function errors
  end
end
```

### line
**Type**: Integer (1-based)
**Description**: Line number where error occurred

### column
**Type**: Integer (1-based)
**Description**: Column number where error occurred

### byte_offset
**Type**: Integer (0-based)
**Description**: Byte offset in input string

### context
**Type**: String
**Description**: Code snippet showing error location with `^` marker

Example:
```ruby
rescue Leptris::XPathError => e
  puts e.context
  # =>  //book[@id = invalid]
  #                  ^
end
```

## Error Handling Patterns

### Pattern 1: Defensive Parsing

```ruby
def safe_parse(xml)
  return nil if xml.nil? || xml.empty?
  
  Leptris.parse(xml)
rescue Leptris::ParseError => e
  logger.error("XML parse failed: #{e.message}")
  logger.debug("Error code: #{e.code}")
  logger.debug("Location: #{e.line}:#{e.column}")
  nil
end
```

### Pattern 2: XPath Validation

```ruby
def validate_xpath(expression)
  # Try to parse (without document context)
  Leptris::XPath.parse(expression)
  true
rescue Leptris::XPathError => e
  warn "Invalid XPath: #{e.message}"
  warn "At: #{e.line}:#{e.column}"
  false
end
```

### Pattern 3: User-Friendly Error Messages

```ruby
def execute_query(doc, xpath)
  doc.xpath(xpath)
rescue Leptris::XPathError => e
  case e.code
  when :xpath_syntax
    "XPath syntax error at position #{e.column}: #{e.message}"
  when :xpath_function
    "Unknown or invalid function: #{e.message}"
  else
    "XPath error: #{e.message}"
  end
end
```

### Pattern 4: Comprehensive Logging

```ruby
def parse_with_logging(xml, source_name)
  logger.info("Parsing XML from: #{source_name}")
  Leptris.parse(xml)
rescue Leptris::ParseError => e
  logger.error("Parse failed for #{source_name}")
  logger.error("  Message: #{e.message}")
  logger.error("  Code: #{e.code}")
  logger.error("  Location: line #{e.line}, column #{e.column}")
  logger.error("  Byte offset: #{e.byte_offset}")
  logger.debug("  Context:\n#{e.context}")
  raise
end
```

## Troubleshooting Guide

### "Empty input provided"

**Problem**: Trying to parse empty XML
**Check**: 
- Is your XML source returning data?
- Are you reading from the correct file/URL?
- Is the network request succeeding?

### "Unclosed tag"

**Problem**: Missing closing tag in XML
**Check**:
- Count opening vs closing tags
- Look for self-closing tags that should be regular tags
- Check nesting hierarchy

### "Unknown function"

**Problem**: Using non-XPath 1.0 function
**Check**:
- Is the function name spelled correctly?
- Is this an XPath 2.0/3.0 function? (not supported yet)
- See list of 27 supported functions above

### "Unexpected token"

**Problem**: Syntax error in XPath
**Check**:
- Are all brackets balanced? `[...]`, `(...)`, `{...}`
- Are strings properly quoted? `'...'` or `"..."`
- Are operators used correctly? `=`, `!=`, `<`, `>`, etc.

## Performance Considerations

### Error Context Generation

Error context generation is optimized but has minimal overhead:

**Cost**: ~1-2µs per error (only when error occurs)
**Impact**: Zero impact on success path
**Memory**: Temporary allocation, immediately freed

### Best Practices

1. **Validate early**: Check input before processing
2. **Cache expressions**: Parse XPath once, reuse
3. **Handle at boundaries**: Catch errors at API boundaries
4. **Log strategically**: Full details to logs, user-friendly to UI

## Related Documentation

- [XPath 1.0 Specification](https://www.w3.org/TR/xpath/)
- [XML 1.0 Specification](https://www.w3.org/TR/xml/)
- [Leptris README](../README.adoc) - Main documentation
- [XPath Spec Compliance](XPATH_SPEC_COMPLIANCE.md) - Feature matrix

## Version History

**v1.0.0** (2024-12-07):
- Initial comprehensive error handling
- All error codes documented
- Context snippets with position markers
- "Did you mean?" suggestions for functions

---

*For implementation details, see `lib/src/error.c` and `lib/leptris/ffi/errors.rb`*