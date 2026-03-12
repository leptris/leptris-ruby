/* libtaurus - Pure C XML/XPath library
 * Copyright (c) 2024, Ribose Inc.
 * All rights reserved.
 *
 * Public API header - No Ruby dependencies
 */

#ifndef LIBTAURUS_H
#define LIBTAURUS_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Opaque Types - Hide implementation details
 * ============================================================================ */

typedef struct taurus_document*     TaurusDocument;
typedef struct taurus_element*      TaurusElement;
typedef struct taurus_attribute*    TaurusAttribute;
typedef struct taurus_namespace*    TaurusNamespace;
typedef struct taurus_xpath_result* TaurusXPathResult;

/* ============================================================================
 * Status Codes
 * ============================================================================ */

typedef enum {
    TAURUS_OK = 0,
    TAURUS_ERROR_MEMORY = -1,      /* Memory allocation failed */
    TAURUS_ERROR_PARSE = -2,       /* XML parsing error */
    TAURUS_ERROR_XPATH = -3,       /* XPath evaluation error */
    TAURUS_ERROR_NULL_ARG = -4,    /* NULL argument passed */
    TAURUS_ERROR_INVALID_ARG = -5, /* Invalid argument */
    TAURUS_ERROR_NOT_FOUND = -6    /* Resource not found */
} TaurusStatus;

/* ============================================================================
 * XPath Result Types
 * ============================================================================ */

typedef enum {
    TAURUS_XPATH_NODESET,
    TAURUS_XPATH_BOOLEAN,
    TAURUS_XPATH_NUMBER,
    TAURUS_XPATH_STRING
} TaurusXPathResultType;

/* ============================================================================
 * Document Operations
 * ============================================================================ */

/**
 * Parse XML string into document
 * 
 * @param xml XML string (must be valid UTF-8)
 * @param length Length of XML string in bytes
 * @param status Output status code (can be NULL)
 * @return Document handle or NULL on error
 * 
 * Memory: Caller must call taurus_document_free() when done
 * Thread safety: Not thread-safe. One document per thread.
 */
TaurusDocument taurus_parse_string(const char* xml, size_t length, TaurusStatus* status);

/**
 * Free document and all its elements
 * 
 * @param doc Document to free (can be NULL)
 */
void taurus_document_free(TaurusDocument doc);

/**
 * Get root element of document
 * 
 * @param doc Document
 * @return Root element or NULL if document is NULL or empty
 * 
 * Memory: Element is owned by document. Do not free separately.
 */
TaurusElement taurus_document_root(TaurusDocument doc);

/* ============================================================================
 * Element Operations
 * ============================================================================ */

/**
 * Get element name
 * 
 * @param elem Element
 * @return Element name or NULL if elem is NULL
 * 
 * Memory: String is owned by element. Do not free or modify.
 */
const char* taurus_element_name(TaurusElement elem);

/**
 * Get element text content (concatenation of all text nodes)
 * 
 * @param elem Element
 * @return Text content or NULL if elem is NULL or has no text
 * 
 * Memory: String is owned by element. Do not free or modify.
 */
const char* taurus_element_text(TaurusElement elem);

/**
 * Get attribute value by name
 * 
 * @param elem Element
 * @param name Attribute name
 * @return Attribute value or NULL if not found
 * 
 * Memory: String is owned by element. Do not free or modify.
 */
const char* taurus_element_attribute(TaurusElement elem, const char* name);

/**
 * Get number of child elements
 * 
 * @param elem Element
 * @return Number of children or 0 if elem is NULL
 */
size_t taurus_element_child_count(TaurusElement elem);

/**
 * Get child element by index
 * 
 * @param elem Element
 * @param index Child index (0-based)
 * @return Child element or NULL if index out of bounds
 * 
 * Memory: Element is owned by document. Do not free separately.
 */
TaurusElement taurus_element_child(TaurusElement elem, size_t index);

/**
 * Get parent element
 * 
 * @param elem Element
 * @return Parent element or NULL if elem is root or NULL
 * 
 * Memory: Element is owned by document. Do not free separately.
 */
TaurusElement taurus_element_parent(TaurusElement elem);

/* ============================================================================
 * Namespace Operations
 * ============================================================================ */

/**
 * Get element's active namespace
 * 
 * @param elem Element
 * @return Namespace or NULL if elem has no namespace
 * 
 * Memory: Namespace is owned by element. Do not free separately.
 */
TaurusNamespace taurus_element_namespace(TaurusElement elem);

/**
 * Get namespace URI
 * 
 * @param ns Namespace
 * @return URI string or NULL if ns is NULL
 * 
 * Memory: String is owned by namespace. Do not free or modify.
 */
const char* taurus_namespace_uri(TaurusNamespace ns);

/**
 * Get namespace prefix
 * 
 * @param ns Namespace
 * @return Prefix string or NULL if default namespace or ns is NULL
 * 
 * Memory: String is owned by namespace. Do not free or modify.
 */
const char* taurus_namespace_prefix(TaurusNamespace ns);

/**
 * Resolve namespace prefix (with inheritance)
 * 
 * @param elem Element to start search from
 * @param prefix Prefix to resolve (NULL for default namespace)
 * @return Namespace URI or NULL if not found
 * 
 * Memory: String is owned by element. Do not free or modify.
 */
const char* taurus_element_namespace_for_prefix(TaurusElement elem, const char* prefix);

/* ============================================================================
 * XPath Operations
 * ============================================================================ */

/**
 * Evaluate XPath expression
 * 
 * @param doc Document (required)
 * @param context Context element (NULL = document root)
 * @param expression XPath expression string
 * @return XPath result or NULL on error
 * 
 * Memory: Caller must call taurus_xpath_result_free() when done
 * Thread safety: Not thread-safe. One evaluation per thread.
 * 
 * XPath 1.0 compliance: Full XPath 1.0 specification
 * - All 13 axes: child, descendant, parent, ancestor, sibling, etc.
 * - All 27 functions: string(), count(), position(), etc.
 * - All operators: =, !=, <, <=, >, >=, +, -, *, div, mod, |, and, or
 * - Predicates: [1], [@attr], [position() > 2], etc.
 */
TaurusXPathResult taurus_xpath_eval(
    TaurusDocument doc,
    TaurusElement context,
    const char* expression
);

/**
 * Get XPath result type
 * 
 * @param result XPath result
 * @return Result type or -1 if result is NULL
 */
TaurusXPathResultType taurus_xpath_result_type(TaurusXPathResult result);

/**
 * Get nodeset size (for NODESET results)
 * 
 * @param result XPath result
 * @return Number of nodes or 0 if not a nodeset or result is NULL
 */
size_t taurus_xpath_result_count(TaurusXPathResult result);

/**
 * Get node from nodeset by index
 * 
 * @param result XPath result
 * @param index Node index (0-based)
 * @return Element or NULL if index out of bounds or not a nodeset
 * 
 * Memory: Element is owned by document. Do not free separately.
 */
TaurusElement taurus_xpath_result_get(TaurusXPathResult result, size_t index);

/**
 * Get boolean value (for BOOLEAN results or type conversion)
 * 
 * @param result XPath result
 * @return Boolean value (1 = true, 0 = false)
 * 
 * Type conversion rules:
 * - BOOLEAN: Direct value
 * - NUMBER: true if non-zero and not NaN
 * - STRING: true if non-empty
 * - NODESET: true if non-empty
 */
int taurus_xpath_result_boolean(TaurusXPathResult result);

/**
 * Get number value (for NUMBER results or type conversion)
 * 
 * @param result XPath result
 * @return Number value (NaN if conversion fails)
 * 
 * Type conversion rules:
 * - NUMBER: Direct value
 * - BOOLEAN: 1.0 or 0.0
 * - STRING: Parsed as number (NaN if invalid)
 * - NODESET: First node's string value converted to number
 */
double taurus_xpath_result_number(TaurusXPathResult result);

/**
 * Get string value (for STRING results or type conversion)
 * 
 * @param result XPath result
 * @return String value or NULL if result is NULL
 * 
 * Memory: Caller must call taurus_free_string() when done
 * 
 * Type conversion rules:
 * - STRING: Direct value
 * - BOOLEAN: "true" or "false"
 * - NUMBER: String representation of number
 * - NODESET: String value of first node (recursive text concatenation)
 */
char* taurus_xpath_result_string(TaurusXPathResult result);

/**
 * Free XPath result
 * 
 * @param result Result to free (can be NULL)
 */
void taurus_xpath_result_free(TaurusXPathResult result);

/* ============================================================================
 * Memory Management Helpers
 * ============================================================================ */

/**
 * Free string returned by libtaurus
 * 
 * @param str String to free (can be NULL)
 * 
 * Use this to free strings returned by:
 * - taurus_xpath_result_string()
 */
void taurus_free_string(char* str);

/* ============================================================================
 * Version Information
 * ============================================================================ */

#define LIBTAURUS_VERSION_MAJOR 0
#define LIBTAURUS_VERSION_MINOR 4
#define LIBTAURUS_VERSION_PATCH 0
#define LIBTAURUS_VERSION_STRING "0.4.0"

/**
 * Get libtaurus version string
 * 
 * @return Version string (e.g., "0.4.0")
 */
const char* taurus_version(void);

#ifdef __cplusplus
}
#endif

#endif /* LIBTAURUS_H */