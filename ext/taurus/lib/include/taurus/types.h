/* types.h - Taurus public type definitions
 * Copyright (c) 2024, Ribose Inc.
 *
 * Public type definitions for libtaurus
 */

#ifndef TAURUS_TYPES_H
#define TAURUS_TYPES_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * API Export/Import Macros
 * ============================================================================ */

#if defined(_WIN32) || defined(__CYGWIN__)
  #ifdef TAURUS_BUILDING_DLL
    #define TAURUS_API __declspec(dllexport)
  #elif defined(TAURUS_DLL)
    #define TAURUS_API __declspec(dllimport)
  #else
    #define TAURUS_API
  #endif
#else
  #if __GNUC__ >= 4
    #define TAURUS_API __attribute__((visibility("default")))
  #else
    #define TAURUS_API
  #endif
#endif

/* ============================================================================
 * Opaque Types
 * ============================================================================ */

/**
 * @brief Opaque document structure
 * 
 * Represents a parsed XML document. The internal structure is hidden
 * from users to maintain API stability.
 */
typedef struct taurus_document taurus_document;

/**
 * @brief Opaque element structure
 * 
 * Represents an XML element node. The internal structure is hidden
 * from users to maintain API stability.
 */
typedef struct taurus_element taurus_element;

/**
 * @brief Opaque attribute structure
 * 
 * Represents an XML attribute. The internal structure is hidden
 * from users to maintain API stability.
 */
typedef struct taurus_attribute taurus_attribute;

/**
 * @brief Opaque namespace structure
 * 
 * Represents an XML namespace declaration. The internal structure is hidden
 * from users to maintain API stability.
 */
typedef struct taurus_namespace taurus_namespace;

/**
 * @brief Opaque XPath result structure
 * 
 * Represents the result of an XPath evaluation. The internal structure is
 * hidden from users to maintain API stability.
 */
typedef struct taurus_xpath_result taurus_xpath_result;

/* ============================================================================
 * Enumerations
 * ============================================================================ */

/**
 * @brief XPath result type enumeration
 * 
 * Defines the four possible result types from XPath 1.0 evaluation.
 */
typedef enum {
    TAURUS_XPATH_BOOLEAN = 0,  /**< Boolean result (true/false) */
    TAURUS_XPATH_NUMBER = 1,   /**< Number result (double) */
    TAURUS_XPATH_STRING = 2,   /**< String result */
    TAURUS_XPATH_NODESET = 3   /**< Node-set result (array of elements) */
} taurus_xpath_result_type;

/**
 * @brief Error codes
 *
 * Error codes returned by all Taurus functions.
 * Organized by category (parse, XPath, evaluation, generic).
 */
typedef enum {
    /* Success */
    TAURUS_OK = 0,                /**< Success */
    
    /* Parse errors (1xx) - XML parsing issues */
    TAURUS_ERROR_NULL_INPUT = 1,        /**< NULL input provided */
    TAURUS_ERROR_EMPTY_INPUT = 2,       /**< Empty input provided */
    TAURUS_ERROR_PARSE_FAILED = 3,      /**< Parse failed (malformed XML) */
    TAURUS_ERROR_INVALID_XML = 4,       /**< Invalid XML structure */
    TAURUS_ERROR_UNCLOSED_TAG = 100,    /**< Element tag not closed */
    TAURUS_ERROR_INVALID_ATTR = 101,    /**< Invalid attribute syntax */
    TAURUS_ERROR_ENCODING = 102,        /**< Encoding error */
    TAURUS_ERROR_NAMESPACE = 103,       /**< Namespace error */
    TAURUS_ERROR_MALFORMED = 104,       /**< Malformed XML */
    
    /* XPath errors (2xx) - Query syntax and semantics */
    TAURUS_ERROR_XPATH_SYNTAX = 200,      /**< XPath syntax error */
    TAURUS_ERROR_XPATH_FUNCTION = 201,    /**< Unknown or invalid function */
    TAURUS_ERROR_XPATH_TYPE_MISMATCH = 202, /**< Type mismatch in operation */
    TAURUS_ERROR_XPATH_NAMESPACE = 203,   /**< Unregistered namespace prefix */
    TAURUS_ERROR_XPATH_UNKNOWN_AXIS = 204, /**< Unknown axis specifier */
    
    /* Evaluation errors (3xx) - Runtime issues */
    TAURUS_ERROR_EVAL_CONTEXT = 300,      /**< Invalid evaluation context */
    TAURUS_ERROR_EVAL_ARGUMENT = 301,     /**< Invalid function argument */
    TAURUS_ERROR_EVAL_OVERFLOW = 302,     /**< Numeric overflow */
    
    /* Generic errors (9xx) */
    TAURUS_ERROR_OUT_OF_MEMORY = 900,     /**< Memory allocation failed */
    TAURUS_ERROR_INTERNAL = 999           /**< Internal error */
} taurus_error_code;

/* ============================================================================
 * Options Structures
 * ============================================================================ */

/**
 * @brief XML parse options
 * 
 * Options that control XML parsing behavior.
 */
typedef struct {
    int strict;              /**< Strict XML validation (1=strict, 0=lenient) */
    int preserve_whitespace; /**< Preserve whitespace-only text nodes */
    int track_positions;     /**< Track line/column positions for errors */
} taurus_parse_options;

#ifdef __cplusplus
}
#endif

#endif /* TAURUS_TYPES_H */