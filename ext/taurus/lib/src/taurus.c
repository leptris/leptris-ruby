/* taurus.c - Taurus public API implementation
 * Copyright (c) 2024, Ribose Inc.
 *
 * Pure C XML parser and XPath evaluator - Public API.
 */

#include "taurus/taurus.h"
#include "taurus_internal.h"
#include "xpath/parser.h"
#include "xpath/evaluator.h"
#include <string.h>

/* Forward declaration from parse_simple.c */
extern struct taurus_document* parse_xml_simple(const char* xml, size_t len);
extern void free_element(struct taurus_element* elem);

/* ============================================================================
 * Version Information
 * ============================================================================ */

/**
 * Get library version string
 */
TAURUS_API const char* taurus_version(void) {
    return TAURUS_VERSION;
}

/**
 * Get version components
 */
TAURUS_API void taurus_version_components(int* major, int* minor, int* patch) {
    if (major) *major = TAURUS_VERSION_MAJOR;
    if (minor) *minor = TAURUS_VERSION_MINOR;
    if (patch) *patch = TAURUS_VERSION_PATCH;
}

/* ============================================================================
 * Parse Options
 * ============================================================================ */

/**
 * Initialize parse options with defaults
 */
TAURUS_API void taurus_parse_options_init(taurus_parse_options* opts) {
    if (!opts) return;
    
    opts->strict = 1;              /* Strict mode by default */
    opts->preserve_whitespace = 0; /* Don't preserve whitespace by default */
    opts->track_positions = 0;     /* Don't track positions by default */
}

/* ============================================================================
 * Document Functions
 * ============================================================================ */

/**
 * Parse XML string into document
 */
TAURUS_API struct taurus_document* taurus_parse(const char* xml, size_t len) {
    if (!xml || len == 0) return NULL;
    
    /* Use default options */
    return parse_xml_simple(xml, len);
}

/**
 * Parse XML with custom options
 */
TAURUS_API struct taurus_document* taurus_parse_with_options(
    const char* xml,
    size_t len,
    const taurus_parse_options* opts
) {
    if (!xml || len == 0) return NULL;
    
    /* For now, ignore options and use simple parser
     * TODO: Implement options support in parser */
    (void)opts; /* Suppress unused parameter warning */
    return parse_xml_simple(xml, len);
}

/**
 * Free document and all its contents
 */
TAURUS_API void taurus_document_free(struct taurus_document* doc) {
    if (!doc) return;
    
    /* Decrement reference count */
    if (doc->ref_count > 0) {
        doc->ref_count--;
        if (doc->ref_count > 0) return;
    }
    
    /* Free root element tree */
    if (doc->root) {
        free_element(doc->root);
    }
    
    /* Free document fields */
    if (doc->encoding) {
        TAURUS_FREE(doc->encoding);
    }
    
    /* Free processing instructions */
    struct taurus_processing_instruction* pi = doc->pis;
    while (pi) {
        struct taurus_processing_instruction* next = pi->next;
        if (pi->target) TAURUS_FREE(pi->target);
        if (pi->data) TAURUS_FREE(pi->data);
        TAURUS_FREE(pi);
        pi = next;
    }
    
    /* Free document */
    TAURUS_FREE(doc);
}

/**
 * Get root element of document
 */
TAURUS_API struct taurus_element* taurus_document_root(struct taurus_document* doc) {
    if (!doc) return NULL;
    return doc->root;
}

/**
 * Get document encoding
 */
TAURUS_API const char* taurus_document_encoding(struct taurus_document* doc) {
    if (!doc) return NULL;
    return doc->encoding; /* May be NULL if not specified */
}

/* ============================================================================
 * Element Functions
 * ============================================================================ */

/**
 * Get element name
 */
TAURUS_API const char* taurus_element_name(struct taurus_element* elem) {
    if (!elem) return "";
    return elem->name ? elem->name : "";
}

/**
 * Get element text content (concatenated recursively)
 */
TAURUS_API const char* taurus_element_text(struct taurus_element* elem) {
    if (!elem) return "";
    
    /* Return direct text content if present */
    if (elem->text_content) {
        return elem->text_content;
    }
    
    /* If no direct text, check if we have children with text */
    /* For now, just return empty string - full recursive concatenation
     * would require allocating memory, which complicates ownership */
    return "";
}

/* ============================================================================
 * XPath Functions
 * ============================================================================ */

/**
 * Evaluate XPath expression against document
 */
TAURUS_API struct taurus_xpath_result* taurus_xpath_eval(
    struct taurus_document* doc,
    const char* xpath_expr,
    size_t expr_len
) {
    if (!doc || !doc->root || !xpath_expr || expr_len == 0) {
        return NULL;
    }
    
    /* Parse XPath expression */
    XPathParser* parser = xpath_parser_new(xpath_expr, expr_len);
    if (!parser) return NULL;
    
    XPathASTNode* ast = xpath_parse(parser);
    const char* parse_error = xpath_parser_error(parser);
    
    if (!ast || parse_error) {
        xpath_parser_free(parser);
        return NULL;
    }
    
    xpath_parser_free(parser);
    
    /* Create evaluation context */
    XPathContext* context = xpath_context_new(doc, doc->root);
    if (!context) {
        ast_node_free(ast);
        return NULL;
    }
    
    /* Evaluate expression */
    struct taurus_xpath_result* result = xpath_evaluate(context, ast);
    
    /* Check for evaluation errors */
    const char* eval_error = xpath_context_error(context);
    if (eval_error && !result) {
        /* Error already set in context */
    }
    
    /* Cleanup */
    xpath_context_free(context);
    ast_node_free(ast);
    
    return result;
}

/**
 * Free XPath result
 */
TAURUS_API void taurus_xpath_result_free(struct taurus_xpath_result* result) {
    /* Use internal xpath_result_free from evaluator */
    xpath_result_free(result);
}