/* xpath.h - Taurus XPath 1.0 API
 * Copyright (c) 2024, Ribose Inc.
 *
 * Complete XPath 1.0 implementation in C
 */

#ifndef TAURUS_XPATH_H
#define TAURUS_XPATH_H

#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * XPath Evaluation
 * ============================================================================ */

/**
 * @brief Evaluate XPath expression against document
 * 
 * Evaluates an XPath 1.0 expression against the given document.
 * The expression is evaluated with the document root as the context node.
 * 
 * @param doc Document to evaluate against (must not be NULL)
 * @param xpath_expr XPath expression string (must not be NULL)
 * @param expr_len Length of expression string
 * @return XPath result, or NULL on error
 * 
 * @note Caller owns the returned result and must free it with
 *       taurus_xpath_result_free()
 * @note Use taurus_last_error() to get error details if NULL is returned
 * 
 * @see taurus_xpath_result_free
 * @see taurus_xpath_eval_with_context
 * 
 * Example:
 * @code
 * taurus_document* doc = taurus_parse(xml, strlen(xml));
 * taurus_xpath_result* result = taurus_xpath_eval(doc, "//book", 6);
 * if (result) {
 *     // Use result...
 *     taurus_xpath_result_free(result);
 * }
 * taurus_document_free(doc);
 * @endcode
 */
TAURUS_API taurus_xpath_result* taurus_xpath_eval(
    taurus_document* doc,
    const char* xpath_expr,
    size_t expr_len
);

/**
 * @brief Evaluate XPath with specific context node
 * 
 * Evaluates an XPath expression with a specific element as the context node.
 * This allows evaluating relative paths from any point in the document.
 * 
 * @param doc Document containing the context node
 * @param context_node Element to use as context (must be in doc)
 * @param xpath_expr XPath expression string
 * @param expr_len Length of expression string
 * @return XPath result, or NULL on error
 * 
 * @note Caller owns the returned result and must free it with
 *       taurus_xpath_result_free()
 * 
 * Example:
 * @code
 * taurus_element* root = taurus_document_root(doc);
 * taurus_xpath_result* result = taurus_xpath_eval_with_context(
 *     doc, root, "./child", 7
 * );
 * @endcode
 */
TAURUS_API taurus_xpath_result* taurus_xpath_eval_with_context(
    taurus_document* doc,
    taurus_element* context_node,
    const char* xpath_expr,
    size_t expr_len
);

/* ============================================================================
 * XPath Result Management
 * ============================================================================ */

/**
 * @brief Free XPath result
 * 
 * Frees all memory associated with an XPath result, including any
 * node-sets, strings, or other data contained in the result.
 * 
 * @param result Result to free (can be NULL)
 * 
 * @note After calling this function, the result pointer is invalid
 *       and should not be used
 */
TAURUS_API void taurus_xpath_result_free(taurus_xpath_result* result);

/**
 * @brief Get result type
 * 
 * Returns the type of an XPath result (boolean, number, string, or node-set).
 * 
 * @param result Result to query (must not be NULL)
 * @return Result type
 * 
 * @see taurus_xpath_result_type
 */
TAURUS_API taurus_xpath_result_type taurus_xpath_result_get_type(
    const taurus_xpath_result* result
);

/* ============================================================================
 * Boolean Results
 * ============================================================================ */

/**
 * @brief Get boolean value from result
 * 
 * Returns the boolean value of a result. If the result is not a boolean,
 * it is converted according to XPath 1.0 rules:
 * - Number: false if 0 or NaN, true otherwise
 * - String: false if empty, true otherwise
 * - Node-set: false if empty, true otherwise
 * 
 * @param result Result to convert (must not be NULL)
 * @return Boolean value (0=false, 1=true)
 */
TAURUS_API int taurus_xpath_result_as_boolean(const taurus_xpath_result* result);

/* ============================================================================
 * Number Results
 * ============================================================================ */

/**
 * @brief Get number value from result
 * 
 * Returns the numeric value of a result. If the result is not a number,
 * it is converted according to XPath 1.0 rules:
 * - Boolean: 0.0 if false, 1.0 if true
 * - String: parsed as number (NaN if invalid)
 * - Node-set: string-value of first node, then parsed
 * 
 * @param result Result to convert (must not be NULL)
 * @return Numeric value (may be NaN or infinity)
 */
TAURUS_API double taurus_xpath_result_as_number(const taurus_xpath_result* result);

/* ============================================================================
 * String Results
 * ============================================================================ */

/**
 * @brief Get string value from result
 * 
 * Returns the string value of a result. If the result is not a string,
 * it is converted according to XPath 1.0 rules:
 * - Boolean: "true" or "false"
 * - Number: number as string
 * - Node-set: string-value of first node
 * 
 * @param result Result to convert (must not be NULL)
 * @return String value (never NULL, but may be empty string)
 * 
 * @note Caller must free the returned string with free()
 * @note Always returns a new allocated string
 */
TAURUS_API char* taurus_xpath_result_as_string(const taurus_xpath_result* result);

/* ============================================================================
 * Node-set Results
 * ============================================================================ */

/**
 * @brief Get node-set size
 * 
 * Returns the number of nodes in a node-set result.
 * If the result is not a node-set, returns 0.
 * 
 * @param result Result to query (must not be NULL)
 * @return Number of nodes (0 if not a node-set)
 */
TAURUS_API size_t taurus_xpath_result_nodeset_size(
    const taurus_xpath_result* result
);

/**
 * @brief Get node from node-set
 * 
 * Returns the node at the specified index in a node-set result.
 * Nodes are returned in document order.
 * 
 * @param result Result to query (must not be NULL)
 * @param index Index of node (0-based)
 * @return Element at index, or NULL if index out of bounds or not a node-set
 * 
 * @note The returned element is owned by the document, not the result
 * @note Do not free the returned element
 */
TAURUS_API taurus_element* taurus_xpath_result_nodeset_get(
    const taurus_xpath_result* result,
    size_t index
);

/* ============================================================================
 * XPath Function Support
 * ============================================================================ */

/**
 * @brief Check if XPath function is supported
 * 
 * Checks if a specific XPath function is implemented and available.
 * All 27 core XPath 1.0 functions are supported.
 * 
 * @param function_name Function name to check (e.g., "count", "string-length")
 * @return 1 if supported, 0 if not
 * 
 * Supported functions:
 * - Node-set: last(), position(), count(), id(), local-name(), namespace-uri(), name()
 * - String: string(), concat(), starts-with(), contains(), substring-before(),
 *           substring-after(), substring(), string-length(), normalize-space(),
 *           translate()
 * - Boolean: boolean(), not(), true(), false(), lang()
 * - Number: number(), sum(), floor(), ceiling(), round()
 */
TAURUS_API int taurus_xpath_function_supported(const char* function_name);

/**
 * @brief Get list of supported XPath functions
 * 
 * Returns a NULL-terminated array of function names that are supported.
 * 
 * @return Array of function names (static, do not free)
 * 
 * Example:
 * @code
 * const char** functions = taurus_xpath_supported_functions();
 * for (int i = 0; functions[i] != NULL; i++) {
 *     printf("%s\n", functions[i]);
 * }
 * @endcode
 */
TAURUS_API const char** taurus_xpath_supported_functions(void);

#ifdef __cplusplus
}
#endif

#endif /* TAURUS_XPATH_H */