/* libtaurus - Internal data structures
 * Copyright (c) 2024, Ribose Inc.
 * All rights reserved.
 *
 * INTERNAL HEADER - Not part of public API
 * These structures are implementation details and may change between versions.
 */

#ifndef TAURUS_INTERNAL_H
#define TAURUS_INTERNAL_H

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include "taurus/types.h"  /* For taurus_error_code */

/* ============================================================================
 * Internal Structures - Match ext/taurus/taurus.h but without Ruby
 * ============================================================================ */

/* Processing instruction structure */
struct taurus_processing_instruction {
    char* target;                /* PI target (e.g., "xml-stylesheet") */
    char* data;                  /* PI data/content */
    struct taurus_processing_instruction* next; /* Linked list */
};

/* Document structure */
struct taurus_document {
    struct taurus_element* root;
    char* encoding;              /* UTF-8 assumed, but store if specified */
    struct taurus_processing_instruction* pis;  /* Processing instructions */
    size_t ref_count;            /* Reference counting for memory management */
};

/* Element structure - Matches ext/taurus/taurus.h _element */
struct taurus_element {
    char* name;                  /* Element name (required) */
    char* prefix;                /* Namespace prefix (can be NULL) */
    char* namespace_uri;         /* Resolved namespace URI (can be NULL) */
    
    /* Hierarchy */
    struct taurus_element* parent;
    struct taurus_element** children;
    size_t children_count;
    size_t children_capacity;
    
    /* Attributes */
    struct taurus_attribute** attributes;
    size_t attributes_count;
    size_t attributes_capacity;
    
    /* Namespace declarations (linked list) */
    struct taurus_namespace* namespaces;
    size_t namespaces_count;
    size_t namespaces_capacity;
    
    /* Content */
    char* text_content;          /* Concatenated text content */
    
    /* Document order for XPath */
    long doc_order;              /* -1 = unset, >= 0 = document order index */
};

/* Attribute structure - Matches ext/taurus/taurus.h _attribute */
struct taurus_attribute {
    char* name;                  /* Attribute name (required) */
    char* prefix;                /* Namespace prefix (can be NULL) */
    char* namespace_uri;         /* Resolved namespace URI (can be NULL) */
    char* value;                 /* Attribute value (can be NULL for boolean attrs) */
};

/* Namespace structure - Matches ext/taurus/taurus.h _namespace */
struct taurus_namespace {
    char* prefix;                /* Namespace prefix (NULL = default namespace) */
    char* uri;                   /* Namespace URI (required) */
    struct taurus_namespace* next; /* Linked list for multiple declarations */
};

/* ============================================================================
 * XPath Node Type System
 * ============================================================================ */

/* Node type enumeration - supports all XPath node types */
typedef enum {
    TAURUS_NODE_ELEMENT = 0,
    TAURUS_NODE_ATTRIBUTE = 1,
    TAURUS_NODE_TEXT = 2,      /* Future */
    TAURUS_NODE_COMMENT = 3,    /* Future */
    TAURUS_NODE_PI = 4          /* Future */
} TaurusNodeType;

/* Attribute node structure - dedicated type for attribute nodes in XPath */
typedef struct taurus_attribute_node {
    TaurusNodeType node_type;    /* Always TAURUS_NODE_ATTRIBUTE */
    char* name;                  /* Attribute name */
    char* value;                 /* Attribute value */
    char* namespace_uri;         /* Namespace URI (can be NULL) */
    struct taurus_element* owner; /* Owner element */
} TaurusAttributeNode;

/* XPath node union - type-safe wrapper for all XPath node types */
typedef union xpath_node {
    TaurusNodeType type;         /* First field for type checking */
    struct {
        TaurusNodeType node_type;
        struct taurus_element* element;
    } as_element;
    TaurusAttributeNode* as_attribute;
} XPathNode;

/* Type checking macros */
#define XPATH_NODE_TYPE(node) (*(TaurusNodeType*)(node))
#define IS_ELEMENT_NODE(node) ((node) && XPATH_NODE_TYPE(node) == TAURUS_NODE_ELEMENT)
#define IS_ATTRIBUTE_NODE(node) ((node) && XPATH_NODE_TYPE(node) == TAURUS_NODE_ATTRIBUTE)

/* ============================================================================
 * XPath Internal Structures
 * ============================================================================ */

/* XPath token - Matches ext/taurus/xpath.h Token */
typedef struct xpath_token {
    int type;                    /* XPathTokenType */
    const char* value;           /* Token value (points into input, not owned) */
    size_t value_len;
    int line;
    int column;
} XPathToken;

/* XPath lexer - Matches ext/taurus/xpath.h Lexer */
typedef struct xpath_lexer {
    const char* input;           /* Input string (not owned) */
    const char* pos;             /* Current position */
    const char* end;             /* End of input */
    int line;
    int column;
    XPathToken current;
    char error_msg[256];
} XPathLexer;

/* XPath AST node types - From ext/taurus/xpath.h */
typedef enum {
    XPATH_AST_PATH_EXPR,
    XPATH_AST_ABSOLUTE_PATH,
    XPATH_AST_RELATIVE_PATH,
    XPATH_AST_STEP,
    XPATH_AST_AXIS_SPECIFIER,
    XPATH_AST_NODE_TEST,
    XPATH_AST_PREDICATE,
    XPATH_AST_FUNCTION_CALL,
    XPATH_AST_ARGUMENT,
    XPATH_AST_NUMBER,
    XPATH_AST_STRING,
    XPATH_AST_VARIABLE_REFERENCE,
    XPATH_AST_OPERATOR,
    XPATH_AST_NODE_TEST_NAME,
    XPATH_AST_NODE_TEST_TYPE,
    XPATH_AST_NODE_TEST_PI,
    XPATH_AST_NODE_TEST_ALL,
    XPATH_AST_NODE_TEST_ALL_IN_NS
} XPathASTType;

/* XPath AST node - Matches ext/taurus/xpath.h _xpath_ast_node */
typedef struct xpath_ast_node {
    XPathASTType type;
    char* value;                 /* String value (owned by node) */
    double number_value;         /* Number value */
    struct xpath_ast_node** children;
    size_t child_count;
    size_t child_capacity;
    
    /* Namespace support for node tests (v0.8.0) */
    char* prefix;                /* Namespace prefix (NULL if no prefix) */
    char* local_name;            /* Local name part (NULL if not applicable) */
} XPathASTNode;

/* XPath parser - Matches ext/taurus/xpath.h _xpath_parser */
typedef struct xpath_parser {
    XPathLexer* lexer;
    XPathToken* tokens;          /* Token array for lookahead */
    size_t token_count;
    size_t token_pos;
    char error_msg[256];
} XPathParser;

/* XPath nodeset - Holds typed node pointers (elements or attributes) */
typedef struct xpath_nodeset {
    void** nodes;                /* Typed node pointers (element* or TaurusAttributeNode*) */
    size_t count;
    size_t capacity;
    int owns_attributes;         /* If true, free attribute nodes on nodeset_free */
} XPathNodeSet;

/* XPath result types - From ext/taurus/xpath.h */
typedef enum {
    XPATH_RESULT_BOOLEAN,
    XPATH_RESULT_NUMBER,
    XPATH_RESULT_STRING,
    XPATH_RESULT_NODESET
} XPathResultType;

/* XPath result value union */
typedef union {
    int boolean_value;
    double number_value;
    char* string_value;          /* Owned by result */
    XPathNodeSet* nodeset_value; /* Owned by result */
} XPathResultValue;

/* XPath result - Matches ext/taurus/xpath.h _xpath_result */
struct taurus_xpath_result {
    XPathResultType type;
    XPathResultValue value;
};

/* Namespace mapping for XPath context (v0.8.0) */
typedef struct xpath_namespace_mapping {
    char* prefix;                /* Namespace prefix (NULL = default namespace) */
    char* uri;                   /* Namespace URI (required) */
} XPathNamespaceMapping;

/* XPath context - Matches ext/taurus/xpath.h _xpath_context */
typedef struct xpath_context {
    struct taurus_document* document;
    struct taurus_element* context_node;
    size_t context_position;     /* 1-based position in context nodeset */
    size_t context_size;         /* Total size of context nodeset */
    void* function_registry;     /* Opaque function registry */
    char error_msg[256];
    
    /* Namespace support (v0.8.0) */
    XPathNamespaceMapping* namespace_mappings;
    size_t namespace_count;
    size_t namespace_capacity;
    
    /* Error context support (v1.0.0) */
    const char* input;           /* Original XPath expression for error context */
    size_t input_len;            /* Length of input expression */
    
    /* Optimization flags */
    int to_boolean;              /* Only checking existence */
    int max_results;             /* Stop after N results (0 = unlimited) */
    int enable_early_exit;       /* Master switch for early termination */
} XPathContext;

/* XPath operator types - From ext/taurus/xpath.h */
typedef enum {
    XPATH_OP_OR,
    XPATH_OP_AND,
    XPATH_OP_EQUAL,
    XPATH_OP_NOT_EQUAL,
    XPATH_OP_LESS,
    XPATH_OP_LESS_EQUAL,
    XPATH_OP_GREATER,
    XPATH_OP_GREATER_EQUAL,
    XPATH_OP_PLUS,
    XPATH_OP_MINUS,
    XPATH_OP_MULTIPLY,
    XPATH_OP_DIV,
    XPATH_OP_MOD,
    XPATH_OP_UNION,
    XPATH_OP_NEGATION
} XPathOperatorType;

/* XPath axis types - From ext/taurus/xpath.h */
typedef enum {
    XPATH_AXIS_ANCESTOR,
    XPATH_AXIS_ANCESTOR_OR_SELF,
    XPATH_AXIS_ATTRIBUTE,
    XPATH_AXIS_CHILD,
    XPATH_AXIS_DESCENDANT,
    XPATH_AXIS_DESCENDANT_OR_SELF,
    XPATH_AXIS_FOLLOWING,
    XPATH_AXIS_FOLLOWING_SIBLING,
    XPATH_AXIS_NAMESPACE,
    XPATH_AXIS_PARENT,
    XPATH_AXIS_PRECEDING,
    XPATH_AXIS_PRECEDING_SIBLING,
    XPATH_AXIS_SELF
} XPathAxisType;

/* ============================================================================
 * Memory Management Macros
 * ============================================================================ */

/* Use standard C memory functions instead of Ruby macros */
#define TAURUS_ALLOC(type) \
    ((type*)malloc(sizeof(type)))

#define TAURUS_ALLOC_N(type, n) \
    ((type*)malloc(sizeof(type) * (n)))

#define TAURUS_REALLOC_N(ptr, type, n) \
    ((type*)realloc((ptr), sizeof(type) * (n)))

#define TAURUS_FREE(ptr) \
    do { if (ptr) { free(ptr); ptr = NULL; } } while(0)

/* Array growth helper - double capacity when full */
#define TAURUS_GROW_ARRAY(ptr, capacity) \
    do { \
        size_t new_cap = (capacity) == 0 ? 4 : (capacity) * 2; \
        (ptr) = realloc((ptr), new_cap * sizeof(*(ptr))); \
        (capacity) = new_cap; \
    } while(0)

/* ============================================================================
 * Generic Memory Allocation
 * ============================================================================ */

/* Generic malloc wrapper */
static inline void* taurus_malloc(size_t size) {
    return malloc(size);
}

/* Generic realloc wrapper */
static inline void* taurus_realloc(void* ptr, size_t size) {
    return realloc(ptr, size);
}

/* Generic free wrapper */
static inline void taurus_free(void* ptr) {
    free(ptr);
}

/* ============================================================================
 * String Helpers
 * ============================================================================ */

/* NULL-safe string duplication */
static inline char* taurus_strdup(const char* str) {
    if (!str) return NULL;
    size_t len = strlen(str);
    char* dup = (char*)malloc(len + 1);
    if (dup) {
        memcpy(dup, str, len + 1);
    }
    return dup;
}

/* NULL-safe string length */
static inline size_t taurus_strlen(const char* str) {
    return str ? strlen(str) : 0;
}

/* NULL-safe string comparison */
static inline int taurus_strcmp(const char* s1, const char* s2) {
    if (s1 == s2) return 0;
    if (!s1) return -1;
    if (!s2) return 1;
    return strcmp(s1, s2);
}

/* ============================================================================
 * Internal Error Functions (from error.c)
 * ============================================================================ */

/* Set error with basic message */
void taurus_set_error(taurus_error_code code, const char* message);

/* Set error with line/column position */
void taurus_set_parse_error_position(int line, int column);

/* Set error with full context (message, input, position, snippet) */
void taurus_set_error_with_context(
    taurus_error_code code,
    const char* message,
    const char* input,
    size_t byte_offset,
    int line,
    int column
);

/* Extract context snippet from input around error position */
void taurus_extract_context_snippet(
    const char* input,
    size_t offset,
    int error_line,
    char* out_buffer,
    size_t buffer_size
);

#endif /* TAURUS_INTERNAL_H */