/* taurus.h - Taurus public API
 * Copyright (c) 2024, Ribose Inc.
 *
 * Pure C XML parser and XPath evaluator
 * 
 * Taurus is a high-performance XML parser with complete XPath 1.0 support,
 * designed for speed and standards compliance. It provides:
 * - Fast XML parsing (comparable to Ox)
 * - Complete XML Namespaces 1.0 support
 * - Full XPath 1.0 implementation
 * - Zero external dependencies
 * 
 * Basic Usage:
 * @code
 * #include <taurus/taurus.h>
 * 
 * const char* xml = "<root><item>Hello</item></root>";
 * taurus_document* doc = taurus_parse(xml, strlen(xml));
 * if (!doc) {
 *     fprintf(stderr, "Parse error: %s\n", taurus_last_error());
 *     return;
 * }
 * 
 * taurus_element* root = taurus_document_root(doc);
 * const char* name = taurus_element_name(root);
 * printf("Root: %s\n", name);
 * 
 * taurus_document_free(doc);
 * @endcode
 */

#ifndef TAURUS_H
#define TAURUS_H

#include <stddef.h>
#include "types.h"
#include "error.h"
#include "xpath.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Version Information
 * ============================================================================ */

#define TAURUS_VERSION_MAJOR 0
#define TAURUS_VERSION_MINOR 5
#define TAURUS_VERSION_PATCH 0

#define TAURUS_VERSION "0.6.0"

/**
 * @brief Get library version string
 * 
 * Returns the version of the Taurus library as a string.
 * 
 * @return Version string (e.g., "0.6.0")
 * 
 * @note The returned string is statically allocated and should not be freed
 */
TAURUS_API const char* taurus_version(void);

/**
 * @brief Get version components
 * 
 * Returns the version of the Taurus library as integers.
 * 
 * @param major Pointer to store major version (can be NULL)
 * @param minor Pointer to store minor version (can be NULL)
 * @param patch Pointer to store patch version (can be NULL)
 */
TAURUS_API void taurus_version_components(int* major, int* minor, int* patch);

/* ============================================================================
 * Parse Options
 * ============================================================================ */

/**
 * @brief Initialize parse options with defaults
 * 
 * Sets parse options to their default values:
 * - strict: 1 (enabled)
 * - preserve_whitespace: 0 (disabled)
 * - track_positions: 0 (disabled)
 * 
 * @param opts Options structure to initialize (must not be NULL)
 */
TAURUS_API void taurus_parse_options_init(taurus_parse_options* opts);

/* ============================================================================
 * Document Functions
 * ============================================================================ */

/**
 * @brief Parse XML string into document
 * 
 * Parses an XML string and returns a document structure.
 * Uses default parse options (strict mode, no whitespace preservation).
 * 
 * @param xml XML string to parse (need not be null-terminated)
 * @param len Length of XML string in bytes
 * @return Document structure on success, NULL on error
 * 
 * @note Caller owns returned document and must free with taurus_document_free()
 * @note Use taurus_last_error() to get error details if NULL is returned
 * @note The xml string can be freed immediately after parsing
 * 
 * @see taurus_parse_with_options
 * @see taurus_document_free
 * 
 * Example:
 * @code
 * const char* xml = "<root><child>text</child></root>";
 * taurus_document* doc = taurus_parse(xml, strlen(xml));
 * if (!doc) {
 *     fprintf(stderr, "Error: %s\n", taurus_last_error());
 *     return;
 * }
 * // Use document...
 * taurus_document_free(doc);
 * @endcode
 */
TAURUS_API taurus_document* taurus_parse(const char* xml, size_t len);

/**
 * @brief Parse XML with custom options
 * 
 * Parses an XML string with custom parse options.
 * 
 * @param xml XML string to parse
 * @param len Length of XML string
 * @param opts Parse options (NULL for defaults)
 * @return Document structure on success, NULL on error
 * 
 * @note Caller owns returned document and must free with taurus_document_free()
 * 
 * Example:
 * @code
 * taurus_parse_options opts;
 * taurus_parse_options_init(&opts);
 * opts.preserve_whitespace = 1;
 * 
 * taurus_document* doc = taurus_parse_with_options(xml, len, &opts);
 * @endcode
 */
TAURUS_API taurus_document* taurus_parse_with_options(
    const char* xml,
    size_t len,
    const taurus_parse_options* opts
);

/**
 * @brief Free document and all its contents
 * 
 * Frees a document and all elements, attributes, and text it contains.
 * 
 * @param doc Document to free (can be NULL)
 * 
 * @note After calling this function, the document pointer and all
 *       elements/attributes obtained from it are invalid
 * @note It is safe to call this function with NULL
 */
TAURUS_API void taurus_document_free(taurus_document* doc);

/**
 * @brief Get root element of document
 * 
 * Returns the root element of a parsed document.
 * 
 * @param doc Document to query (must not be NULL)
 * @return Root element, or NULL if document has no root
 * 
 * @note The returned element is owned by the document
 * @note Do not free the returned element
 */
TAURUS_API taurus_element* taurus_document_root(taurus_document* doc);

/**
 * @brief Get document encoding
 * 
 * Returns the encoding specified in the XML declaration, if any.
 * 
 * @param doc Document to query (must not be NULL)
 * @return Encoding string (e.g., "UTF-8"), or NULL if not specified
 * 
 * @note The returned string is owned by the document
 * @note Do not free the returned string
 */
TAURUS_API const char* taurus_document_encoding(taurus_document* doc);

/* ============================================================================
 * Element Functions
 * ============================================================================ */

/**
 * @brief Get element name
 * 
 * Returns the local name of an element (without namespace prefix).
 * 
 * @param elem Element to query (must not be NULL)
 * @return Element name (never NULL, but may be empty string)
 * 
 * @note The returned string is owned by the element
 * @note Do not free the returned string
 */
TAURUS_API const char* taurus_element_name(taurus_element* elem);

/**
 * @brief Get element namespace URI
 * 
 * Returns the namespace URI of an element.
 * 
 * @param elem Element to query (must not be NULL)
 * @return Namespace URI, or NULL if element has no namespace
 * 
 * @note The returned string is owned by the element
 * @note Do not free the returned string
 */
TAURUS_API const char* taurus_element_namespace(taurus_element* elem);

/**
 * @brief Get element namespace prefix
 * 
 * Returns the namespace prefix used in the element's qualified name.
 * 
 * @param elem Element to query (must not be NULL)
 * @return Namespace prefix, or NULL if element has no prefix
 * 
 * @note The returned string is owned by the element
 * @note Do not free the returned string
 */
TAURUS_API const char* taurus_element_prefix(taurus_element* elem);

/**
 * @brief Get element text content
 * 
 * Returns the concatenated text content of an element and all its descendants.
 * 
 * @param elem Element to query (must not be NULL)
 * @return Text content (never NULL, but may be empty string)
 * 
 * @note The returned string is owned by the element
 * @note Do not free the returned string
 * @note For mixed content, this returns all text nodes concatenated
 */
TAURUS_API const char* taurus_element_text(taurus_element* elem);

/**
 * @brief Get parent element
 * 
 * Returns the parent element of an element.
 * 
 * @param elem Element to query (must not be NULL)
 * @return Parent element, or NULL if element is root
 * 
 * @note The returned element is owned by the document
 * @note Do not free the returned element
 */
TAURUS_API taurus_element* taurus_element_parent(taurus_element* elem);

/**
 * @brief Get number of child elements
 * 
 * Returns the number of direct child elements.
 * 
 * @param elem Element to query (must not be NULL)
 * @return Number of child elements
 * 
 * @note This only counts element children, not text nodes
 */
TAURUS_API size_t taurus_element_child_count(taurus_element* elem);

/**
 * @brief Get child element by index
 * 
 * Returns the child element at the specified index.
 * 
 * @param elem Element to query (must not be NULL)
 * @param index Index of child (0-based)
 * @return Child element, or NULL if index out of bounds
 * 
 * @note The returned element is owned by the document
 * @note Do not free the returned element
 */
TAURUS_API taurus_element* taurus_element_child(taurus_element* elem, size_t index);

/* ============================================================================
 * Attribute Functions
 * ============================================================================ */

/**
 * @brief Get number of attributes
 * 
 * Returns the number of attributes an element has.
 * 
 * @param elem Element to query (must not be NULL)
 * @return Number of attributes
 */
TAURUS_API size_t taurus_element_attribute_count(taurus_element* elem);

/**
 * @brief Get attribute by index
 * 
 * Returns the attribute at the specified index.
 * 
 * @param elem Element to query (must not be NULL)
 * @param index Index of attribute (0-based)
 * @return Attribute, or NULL if index out of bounds
 * 
 * @note The returned attribute is owned by the element
 * @note Do not free the returned attribute
 */
TAURUS_API taurus_attribute* taurus_element_attribute(
    taurus_element* elem,
    size_t index
);

/**
 * @brief Get attribute value by name
 * 
 * Returns the value of an attribute with the specified name.
 * 
 * @param elem Element to query (must not be NULL)
 * @param name Attribute name (must not be NULL)
 * @return Attribute value, or NULL if attribute not found
 * 
 * @note The returned string is owned by the element
 * @note Do not free the returned string
 * @note This searches by local name only (ignores namespaces)
 */
TAURUS_API const char* taurus_element_get_attribute(
    taurus_element* elem,
    const char* name
);

/**
 * @brief Check if element has attribute
 * 
 * Checks if an element has an attribute with the specified name.
 * 
 * @param elem Element to query (must not be NULL)
 * @param name Attribute name (must not be NULL)
 * @return 1 if attribute exists, 0 otherwise
 */
TAURUS_API int taurus_element_has_attribute(
    taurus_element* elem,
    const char* name
);

/**
 * @brief Get attribute name
 * 
 * Returns the local name of an attribute.
 * 
 * @param attr Attribute to query (must not be NULL)
 * @return Attribute name (never NULL)
 * 
 * @note The returned string is owned by the attribute
 * @note Do not free the returned string
 */
TAURUS_API const char* taurus_attribute_name(taurus_attribute* attr);

/**
 * @brief Get attribute value
 * 
 * Returns the value of an attribute.
 * 
 * @param attr Attribute to query (must not be NULL)
 * @return Attribute value (never NULL, but may be empty string)
 * 
 * @note The returned string is owned by the attribute
 * @note Do not free the returned string
 */
TAURUS_API const char* taurus_attribute_value(taurus_attribute* attr);

/**
 * @brief Get attribute namespace URI
 * 
 * Returns the namespace URI of an attribute.
 * 
 * @param attr Attribute to query (must not be NULL)
 * @return Namespace URI, or NULL if attribute has no namespace
 * 
 * @note The returned string is owned by the attribute
 * @note Do not free the returned string
 */
TAURUS_API const char* taurus_attribute_namespace(taurus_attribute* attr);

/* ============================================================================
 * Namespace Functions
 * ============================================================================ */

/**
 * @brief Get number of namespace declarations
 * 
 * Returns the number of namespace declarations on an element.
 * 
 * @param elem Element to query (must not be NULL)
 * @return Number of namespace declarations
 * 
 * @note This only counts declarations on this element, not inherited ones
 */
TAURUS_API size_t taurus_element_namespace_count(taurus_element* elem);

/**
 * @brief Get namespace declaration by index
 * 
 * Returns the namespace declaration at the specified index.
 * 
 * @param elem Element to query (must not be NULL)
 * @param index Index of namespace (0-based)
 * @return Namespace declaration, or NULL if index out of bounds
 * 
 * @note The returned namespace is owned by the element
 * @note Do not free the returned namespace
 */
TAURUS_API taurus_namespace* taurus_element_namespace_decl(
    taurus_element* elem,
    size_t index
);

/**
 * @brief Resolve namespace prefix
 * 
 * Resolves a namespace prefix to its URI, considering inheritance.
 * 
 * @param elem Element to start search from (must not be NULL)
 * @param prefix Namespace prefix to resolve (NULL for default namespace)
 * @return Namespace URI, or NULL if prefix not found
 * 
 * @note The returned string is owned by the document
 * @note Do not free the returned string
 * @note Searches up the element tree to find matching declaration
 */
TAURUS_API const char* taurus_element_resolve_namespace(
    taurus_element* elem,
    const char* prefix
);

/**
 * @brief Get namespace prefix
 * 
 * Returns the prefix of a namespace declaration.
 * 
 * @param ns Namespace to query (must not be NULL)
 * @return Namespace prefix, or NULL for default namespace
 * 
 * @note The returned string is owned by the namespace
 * @note Do not free the returned string
 */
TAURUS_API const char* taurus_namespace_prefix(taurus_namespace* ns);

/**
 * @brief Get namespace URI
 * 
 * Returns the URI of a namespace declaration.
 * 
 * @param ns Namespace to query (must not be NULL)
 * @return Namespace URI (never NULL)
 * 
 * @note The returned string is owned by the namespace
 * @note Do not free the returned string
 */
TAURUS_API const char* taurus_namespace_uri(taurus_namespace* ns);

#ifdef __cplusplus
}
#endif

#endif /* TAURUS_H */