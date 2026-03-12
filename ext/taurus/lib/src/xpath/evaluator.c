/* evaluator.c - XPath evaluator implementation
 * Copyright (c) 2024, Ribose Inc.
 *
 * Pure C implementation of XPath 1.0 evaluator.
 * Converted from Ruby C extension to pure C.
 */

#include "evaluator.h"
#include "functions.h"
#include "lexer.h"
#include "parser.h"
#include "taurus/taurus.h"
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <ctype.h>

/* Debug logging - set to 1 to enable */
#define XPATH_DEBUG 0

#if XPATH_DEBUG
#define DEBUG_LOG(fmt, ...) fprintf(stderr, "[XPath DEBUG] " fmt "\n", ##__VA_ARGS__)
#else
#define DEBUG_LOG(fmt, ...) do {} while(0)
#endif

/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

/* Namespace support functions (v0.8.0) */
static void xpath_context_register_namespace(XPathContext* context,
                                             const char* prefix,
                                             const char* uri);
static const char* xpath_context_resolve_prefix(XPathContext* context,
                                                const char* prefix);
static void xpath_context_init_from_document(XPathContext* context);

/* Main evaluation dispatcher */
static struct taurus_xpath_result* evaluate_expr(XPathContext* context,
                                                  XPathASTNode* ast);

/* Path evaluation */
static struct taurus_xpath_result* evaluate_location_path(XPathContext* context,
                                                          XPathASTNode* path);
static struct taurus_xpath_result* evaluate_step(XPathContext* context,
                                                 XPathASTNode* step,
                                                 XPathNodeSet* input);

/* Node test matching */
static int matches_node_test(XPathContext* ctx, struct taurus_element* node, XPathASTNode* test);

/* Predicate evaluation */
static XPathNodeSet* apply_predicates(XPathContext* context,
                                     XPathNodeSet* nodes,
                                     XPathASTNode** predicates,
                                     size_t pred_count);

/* Axis implementations */
static XPathNodeSet* apply_axis(XPathContext* context,
                               struct taurus_element* node,
                               const char* axis_name,
                               XPathASTNode* node_test);

/* Operators */
static struct taurus_xpath_result* evaluate_operator(XPathContext* context,
                                                    XPathASTNode* ast);

/* ============================================================================
 * Context Management
 * ============================================================================ */

XPathContext* xpath_context_new(struct taurus_document* document,
                                struct taurus_element* context_node) {
    if (!document || !context_node) return NULL;

    XPathContext* context = TAURUS_ALLOC(XPathContext);
    if (!context) return NULL;

    context->document = document;
    context->context_node = context_node;
    context->context_position = 1;
    context->context_size = 1;
    context->error_msg[0] = '\0';
    context->to_boolean = 0;
    context->max_results = 0;
    context->enable_early_exit = 1;

    /* Initialize namespace support (v0.8.0) */
    context->namespace_mappings = NULL;
    context->namespace_count = 0;
    context->namespace_capacity = 0;

    /* Initialize error context (v1.0.0) */
    context->input = NULL;
    context->input_len = 0;

    /* Initialize function registry with standard XPath 1.0 functions */
    context->function_registry = xpath_function_registry_new();
    if (context->function_registry) {
        xpath_function_registry_init_standard(
            (XPathFunctionRegistry*)context->function_registry);
    }

    /* Auto-populate namespace mappings from document (v0.8.0) */
    xpath_context_init_from_document(context);

    return context;
}

void xpath_context_free(XPathContext* context) {
    if (!context) return;

    /* Free namespace mappings (v0.8.0) */
    if (context->namespace_mappings) {
        for (size_t i = 0; i < context->namespace_count; i++) {
            TAURUS_FREE(context->namespace_mappings[i].prefix);
            TAURUS_FREE(context->namespace_mappings[i].uri);
        }
        TAURUS_FREE(context->namespace_mappings);
    }

    /* Free function registry */
    if (context->function_registry) {
        xpath_function_registry_free((XPathFunctionRegistry*)context->function_registry);
    }

    TAURUS_FREE(context);
}

const char* xpath_context_error(XPathContext* context) {
    if (!context) return "Invalid context";
    return context->error_msg[0] ? context->error_msg : NULL;
}

/* ============================================================================
 * Namespace Support (v0.8.0)
 * ============================================================================ */

/**
 * Register a namespace prefix->URI mapping in the context
 *
 * @param context XPath context
 * @param prefix Namespace prefix (NULL for default namespace)
 * @param uri Namespace URI (required)
 */
void xpath_context_register_namespace(XPathContext* context,
                                      const char* prefix,
                                      const char* uri) {
    if (!context || !uri) return;

    /* Check if prefix already registered - update if found */
    for (size_t i = 0; i < context->namespace_count; i++) {
        int prefix_matches = 0;
        if (!prefix && !context->namespace_mappings[i].prefix) {
            prefix_matches = 1; /* Both NULL (default namespace) */
        } else if (prefix && context->namespace_mappings[i].prefix &&
                   strcmp(prefix, context->namespace_mappings[i].prefix) == 0) {
            prefix_matches = 1; /* Both non-NULL and equal */
        }

        if (prefix_matches) {
            /* Update existing mapping */
            TAURUS_FREE(context->namespace_mappings[i].uri);
            context->namespace_mappings[i].uri = taurus_strdup(uri);
            return;
        }
    }

    /* Add new mapping - grow array if needed */
    if (context->namespace_count >= context->namespace_capacity) {
        size_t new_capacity = context->namespace_capacity == 0 ?
            4 : context->namespace_capacity * 2;
        XPathNamespaceMapping* new_mappings = TAURUS_REALLOC_N(
            context->namespace_mappings,
            XPathNamespaceMapping,
            new_capacity
        );
        if (!new_mappings) return; /* Allocation failed */

        context->namespace_mappings = new_mappings;
        context->namespace_capacity = new_capacity;
    }

    /* Add new mapping */
    context->namespace_mappings[context->namespace_count].prefix =
        prefix ? taurus_strdup(prefix) : NULL;
    context->namespace_mappings[context->namespace_count].uri =
        taurus_strdup(uri);
    context->namespace_count++;
}

/**
 * Resolve namespace prefix to URI (OPTIMIZED with reverse lookup)
 *
 * Strategy: Search from END to START to find most recent registration first.
 * This handles override semantics naturally - child namespace declarations
 * override parent ones because they're registered later.
 *
 * Performance: O(n) worst case, but in practice very fast because:
 * - Most documents have <10 unique namespace prefixes
 * - Recent registrations (local scope) found first
 * - Common prefixes cached by compiler in registers
 *
 * @param context XPath context
 * @param prefix Namespace prefix to resolve (NULL for default namespace)
 * @return Namespace URI, or NULL if not found
 */
const char* xpath_context_resolve_prefix(XPathContext* context,
                                         const char* prefix) {
    if (!context || context->namespace_count == 0) return NULL;

    /* Search BACKWARDS for most recent (local) registration first
     * This implements namespace scope override semantics efficiently */
    for (size_t i = context->namespace_count; i > 0; i--) {
        size_t idx = i - 1;
        XPathNamespaceMapping* mapping = &context->namespace_mappings[idx];

        /* Fast path: Compare prefix pointers first (common case: same string object) */
        if (mapping->prefix == prefix) {
            return mapping->uri;
        }

        /* Both NULL = default namespace match */
        if (!prefix && !mapping->prefix) {
            return mapping->uri;
        }

        /* String comparison only if both non-NULL */
        if (prefix && mapping->prefix && strcmp(prefix, mapping->prefix) == 0) {
            return mapping->uri;
        }
    }

    return NULL; /* Prefix not found */
}

/* Helper: Collect namespaces from element and all descendants recursively */
static void collect_namespaces_recursive(XPathContext* context,
                                         struct taurus_element* element) {
    if (!element) return;

    /* Register namespaces from this element's namespace declarations
     * Note: namespaces is a linked list, not an array */
    struct taurus_namespace* ns = element->namespaces;
    while (ns) {
        if (ns->uri) {
            xpath_context_register_namespace(context, ns->prefix, ns->uri);
        }
        ns = ns->next;
    }

    /* Also check attributes for xmlns declarations
     * (in case they weren't already parsed into namespaces list) */
    for (size_t i = 0; i < element->attributes_count; i++) {
        struct taurus_attribute* attr = element->attributes[i];
        if (!attr || !attr->name) continue;

        /* Check for xmlns:prefix or xmlns */
        if (strncmp(attr->name, "xmlns:", 6) == 0) {
            /* xmlns:prefix="uri" */
            xpath_context_register_namespace(context, attr->name + 6, attr->value);
        } else if (strcmp(attr->name, "xmlns") == 0) {
            /* xmlns="uri" (default namespace) */
            xpath_context_register_namespace(context, NULL, attr->value);
        }
    }

    /* Recursively collect from children */
    for (size_t i = 0; i < element->children_count; i++) {
        collect_namespaces_recursive(context, element->children[i]);
    }
}

/**
 * Auto-populate namespace mappings from entire document tree
 *
 * @param context XPath context
 */
void xpath_context_init_from_document(XPathContext* context) {
    if (!context || !context->document || !context->document->root) return;

    /* Collect namespaces from entire document tree
     * This ensures namespace declarations on any element are available */
    collect_namespaces_recursive(context, context->document->root);
}

/* ============================================================================
 * NodeSet Management
 * ============================================================================ */

XPathNodeSet* xpath_nodeset_new(void) {
    return xpath_nodeset_new_with_capacity(0);
}

XPathNodeSet* xpath_nodeset_new_with_capacity(size_t capacity) {
    XPathNodeSet* nodeset = TAURUS_ALLOC(XPathNodeSet);
    if (!nodeset) return NULL;

    if (capacity > 0) {
        nodeset->nodes = (void**)TAURUS_ALLOC_N(void*, capacity);
        if (!nodeset->nodes) {
            TAURUS_FREE(nodeset);
            return NULL;
        }
        nodeset->capacity = capacity;
    } else {
        nodeset->nodes = NULL;
        nodeset->capacity = 0;
    }

    nodeset->count = 0;
    nodeset->owns_attributes = 1;  /* By default, nodeset owns its attribute nodes */
    return nodeset;
}

void xpath_nodeset_free(XPathNodeSet* nodeset) {
    if (!nodeset) return;

    if (nodeset->nodes && nodeset->owns_attributes) {
        /* Free typed nodes only if we own them - check node type and free appropriately */
        for (size_t i = 0; i < nodeset->count; i++) {
            void* node = nodeset->nodes[i];
            if (!node) continue;

            TaurusNodeType node_type = XPATH_NODE_TYPE(node);
            if (node_type == TAURUS_NODE_ATTRIBUTE) {
                /* Attribute node - free its allocated memory */
                TaurusAttributeNode* attr_node = (TaurusAttributeNode*)node;
                if (attr_node->name) TAURUS_FREE(attr_node->name);
                if (attr_node->value) TAURUS_FREE(attr_node->value);
                if (attr_node->namespace_uri) TAURUS_FREE(attr_node->namespace_uri);
                TAURUS_FREE(attr_node);
            }
            /* Element nodes are owned by document, don't free */
        }
    }
    if (nodeset->nodes) {
        TAURUS_FREE(nodeset->nodes);
    }
    TAURUS_FREE(nodeset);
}

size_t xpath_nodeset_count(XPathNodeSet* nodeset) {
    return nodeset ? nodeset->count : 0;
}

void* xpath_nodeset_get(XPathNodeSet* nodeset, size_t index) {
    if (!nodeset || !nodeset->nodes || index >= nodeset->count) {
        return NULL;
    }
    return nodeset->nodes[index];
}

void xpath_nodeset_add(XPathNodeSet* nodeset, void* node) {
    if (!nodeset || !node) return;

    /* Resize if needed */
    if (nodeset->count >= nodeset->capacity) {
        size_t new_capacity = nodeset->capacity == 0 ? 8 : nodeset->capacity * 2;
        void** new_nodes = (void**)TAURUS_REALLOC_N(
            nodeset->nodes, void*, new_capacity);
        if (!new_nodes) return;
        nodeset->nodes = new_nodes;
        nodeset->capacity = new_capacity;
    }

    nodeset->nodes[nodeset->count++] = node;
}

/* Helper: Create attribute node from taurus_attribute */
static TaurusAttributeNode* create_attribute_node(struct taurus_attribute* attr,
                                                   struct taurus_element* owner) {
    if (!attr) return NULL;

    TaurusAttributeNode* attr_node = TAURUS_ALLOC(TaurusAttributeNode);
    if (!attr_node) return NULL;

    attr_node->node_type = TAURUS_NODE_ATTRIBUTE;
    attr_node->name = taurus_strdup(attr->name);
    attr_node->value = taurus_strdup(attr->value);
    attr_node->namespace_uri = attr->namespace_uri ? taurus_strdup(attr->namespace_uri) : NULL;
    attr_node->owner = owner;

    return attr_node;
}

/* Helper: Get element from typed node (returns NULL if not element)
 *
 * IMPORTANT: Elements are stored as plain taurus_element* without a type field.
 * Only attribute nodes have a node_type field as their first member.
 *
 * Strategy: Check if first field is TAURUS_NODE_ATTRIBUTE. If so, it's an attribute.
 * Otherwise, treat it as an element.
 */
static struct taurus_element* node_as_element(void* node) {
    if (!node) return NULL;

    /* Check if it's an attribute node by reading first field */
    TaurusNodeType first_field = *(TaurusNodeType*)node;
    if (first_field == TAURUS_NODE_ATTRIBUTE) {
        /* It's an attribute node, not an element */
        return NULL;
    }

    /* Otherwise, it's an element (no type field in taurus_element) */
    return (struct taurus_element*)node;
}

/* Helper: Get attribute node from typed node (returns NULL if not attribute) */
static TaurusAttributeNode* node_as_attribute(void* node) {
    if (!node) return NULL;

    /* Check if first field is TAURUS_NODE_ATTRIBUTE */
    TaurusNodeType first_field = *(TaurusNodeType*)node;
    return (first_field == TAURUS_NODE_ATTRIBUTE) ? (TaurusAttributeNode*)node : NULL;
}

/* ============================================================================
 * Result Management
 * ============================================================================ */

struct taurus_xpath_result* xpath_result_new(XPathResultType type) {
    struct taurus_xpath_result* result = TAURUS_ALLOC(struct taurus_xpath_result);
    if (!result) return NULL;

    result->type = type;
    memset(&result->value, 0, sizeof(XPathResultValue));
    return result;
}

void xpath_result_free(struct taurus_xpath_result* result) {
    if (!result) return;

    switch (result->type) {
        case XPATH_RESULT_STRING:
            if (result->value.string_value) {
                TAURUS_FREE(result->value.string_value);
            }
            break;
        case XPATH_RESULT_NODESET:
            xpath_nodeset_free(result->value.nodeset_value);
            break;
        default:
            break;
    }

    TAURUS_FREE(result);
}

/* ============================================================================
 * Type Conversions (XPath 1.0 Spec Section 4)
 * ============================================================================ */

/* Get text content from typed node (handles elements and attributes) */
static char* get_node_text(void* node) {
    if (!node) return taurus_strdup("");

    TaurusNodeType node_type = XPATH_NODE_TYPE(node);

    switch (node_type) {
        case TAURUS_NODE_ELEMENT: {
            struct taurus_element* element = (struct taurus_element*)node;

            /* If element has direct text content, return it */
            if (element->text_content) {
                return taurus_strdup(element->text_content);
            }

            /* Otherwise concatenate all descendant text */
            size_t total_len = 0;
            size_t capacity = 256;
            char* result = TAURUS_ALLOC_N(char, capacity);
            if (!result) return taurus_strdup("");
            result[0] = '\0';

            /* Recursively collect text from children */
            for (size_t i = 0; i < element->children_count; i++) {
                char* child_text = get_node_text(element->children[i]);
                if (child_text) {
                    size_t child_len = strlen(child_text);
                    if (total_len + child_len + 1 > capacity) {
                        capacity = (total_len + child_len + 1) * 2;
                        char* new_result = TAURUS_REALLOC_N(result, char, capacity);
                        if (!new_result) {
                            TAURUS_FREE(child_text);
                            TAURUS_FREE(result);
                            return taurus_strdup("");
                        }
                        result = new_result;
                    }
                    strcat(result, child_text);
                    total_len += child_len;
                    TAURUS_FREE(child_text);
                }
            }

            return result;
        }

        case TAURUS_NODE_ATTRIBUTE: {
            TaurusAttributeNode* attr_node = (TaurusAttributeNode*)node;
            return taurus_strdup(attr_node->value ? attr_node->value : "");
        }

        default:
            return taurus_strdup("");
    }
}

int xpath_to_boolean(struct taurus_xpath_result* result) {
    if (!result) return 0;

    switch (result->type) {
        case XPATH_RESULT_BOOLEAN:
            return result->value.boolean_value;
        case XPATH_RESULT_NUMBER:
            return result->value.number_value != 0.0 && !isnan(result->value.number_value);
        case XPATH_RESULT_STRING:
            return result->value.string_value && result->value.string_value[0] != '\0';
        case XPATH_RESULT_NODESET:
            return xpath_nodeset_count(result->value.nodeset_value) > 0;
        default:
            return 0;
    }
}

double xpath_to_number(struct taurus_xpath_result* result) {
    if (!result) return NAN;

    switch (result->type) {
        case XPATH_RESULT_NUMBER:
            return result->value.number_value;
        case XPATH_RESULT_BOOLEAN:
            return result->value.boolean_value ? 1.0 : 0.0;
        case XPATH_RESULT_STRING: {
            if (!result->value.string_value) return NAN;
            const char* str = result->value.string_value;

            /* Skip leading whitespace */
            while (isspace((unsigned char)*str)) str++;
            if (*str == '\0') return NAN;

            /* Parse number */
            char* endptr;
            double value = strtod(str, &endptr);

            /* Skip trailing whitespace */
            while (isspace((unsigned char)*endptr)) endptr++;

            /* Must consume entire string */
            return (*endptr == '\0') ? value : NAN;
        }
        case XPATH_RESULT_NODESET: {
            /* Convert first node's string value to number */
            XPathNodeSet* nodeset = result->value.nodeset_value;
            if (!nodeset || xpath_nodeset_count(nodeset) == 0) {
                return NAN;
            }
            void* first = xpath_nodeset_get(nodeset, 0);
            char* str = get_node_text(first);
            if (!str) return NAN;

            /* Parse the string */
            const char* p = str;
            while (isspace((unsigned char)*p)) p++;
            if (*p == '\0') {
                TAURUS_FREE(str);
                return NAN;
            }

            char* endptr;
            double value = strtod(p, &endptr);
            while (isspace((unsigned char)*endptr)) endptr++;

            int valid = (*endptr == '\0');
            TAURUS_FREE(str);
            return valid ? value : NAN;
        }
        default:
            return NAN;
    }
}

char* xpath_to_string(struct taurus_xpath_result* result) {
    if (!result) return taurus_strdup("");

    switch (result->type) {
        case XPATH_RESULT_STRING:
            return taurus_strdup(result->value.string_value ?
                               result->value.string_value : "");
        case XPATH_RESULT_NUMBER: {
            char buf[64];
            double num = result->value.number_value;
            if (isnan(num)) {
                return taurus_strdup("NaN");
            } else if (isinf(num)) {
                return taurus_strdup(num > 0 ? "Infinity" : "-Infinity");
            } else {
                snprintf(buf, sizeof(buf), "%g", num);
                return taurus_strdup(buf);
            }
        }
        case XPATH_RESULT_BOOLEAN:
            return taurus_strdup(result->value.boolean_value ? "true" : "false");
        case XPATH_RESULT_NODESET: {
            XPathNodeSet* nodeset = result->value.nodeset_value;
            if (!nodeset || xpath_nodeset_count(nodeset) == 0) {
                return taurus_strdup("");
            }
            return get_node_text(xpath_nodeset_get(nodeset, 0));
        }
        default:
            return taurus_strdup("");
    }
}

/* ============================================================================
 * Node Test Matching
 * ============================================================================ */

static int matches_node_test(XPathContext* ctx, struct taurus_element* node, XPathASTNode* test) {
    if (!node || !test) return 1;  /* No test means match all */

    switch (test->type) {
        case XPATH_AST_NODE_TEST_NAME:
            /* Match specific name - namespace-aware (v0.8.0) */
            if (!test->value || !node->name) return 0;

            /* If test has no prefix, match local name only (backward compatible) */
            if (!test->prefix) {
                const char* local_name = node->name;
                const char* colon = strchr(node->name, ':');
                if (colon) local_name = colon + 1;

                const char* test_name = test->local_name ? test->local_name : test->value;
                return strcmp(local_name, test_name) == 0;
            }

            /* Test has prefix - need namespace-aware matching */
            /* 1. Resolve test prefix to URI */
            const char* test_uri = xpath_context_resolve_prefix(ctx, test->prefix);
            if (!test_uri) return 0;  /* Unknown prefix */

            /* 2. Get element's namespace URI */
            const char* element_uri = node->namespace_uri;
            if (!element_uri) return 0;  /* Element not in namespace */

            /* 3. Match URIs */
            if (strcmp(test_uri, element_uri) != 0) return 0;

            /* URIs match - now check local name */
            const char* element_local = node->name;
            const char* colon = strchr(node->name, ':');
            if (colon) element_local = colon + 1;

            const char* test_local = test->local_name ? test->local_name : test->value;
            return strcmp(element_local, test_local) == 0;

        case XPATH_AST_NODE_TEST_ALL:
            /* Wildcard - if test has prefix, match namespace (v0.8.0) */
            if (test->prefix) {
                const char* test_uri = xpath_context_resolve_prefix(ctx, test->prefix);
                if (!test_uri) return 0;
                const char* element_uri = node->namespace_uri;
                return element_uri && strcmp(test_uri, element_uri) == 0;
            }
            /* No prefix - match all elements */
            return 1;

        case XPATH_AST_NODE_TEST_TYPE:
            /* Node type tests (node(), text(), etc.) */
            if (test->value) {
                if (strcmp(test->value, "node") == 0) {
                    return 1;  /* node() matches all nodes */
                }
                /* text(), comment() not fully implemented yet */
            }
            return 0;

        default:
            return 0;
    }
}

/* ============================================================================
 * Axis Implementations (All 13 XPath Axes)
 * ============================================================================ */

/* Helper: Collect descendants recursively */
static void collect_descendants(XPathContext* ctx,
                               struct taurus_element* node,
                               XPathNodeSet* result,
                               XPathASTNode* node_test) {
    if (!node) return;

    for (size_t i = 0; i < node->children_count; i++) {
        struct taurus_element* child = node->children[i];
        if (matches_node_test(ctx, child, node_test)) {
            xpath_nodeset_add(result, child);
        }
        collect_descendants(ctx, child, result, node_test);
    }
}

/* Helper: Collect descendants or self */
static void collect_descendants_or_self(XPathContext* ctx,
                                       struct taurus_element* node,
                                       XPathNodeSet* result,
                                       XPathASTNode* node_test) {
    if (!node) return;

    if (matches_node_test(ctx, node, node_test)) {
        xpath_nodeset_add(result, node);
    }

    for (size_t i = 0; i < node->children_count; i++) {
        collect_descendants_or_self(ctx, node->children[i], result, node_test);
    }
}

/* child:: axis */
static XPathNodeSet* axis_child(XPathContext* ctx, struct taurus_element* node,
                               XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node) return result;

    for (size_t i = 0; i < node->children_count; i++) {
        struct taurus_element* child = node->children[i];
        if (matches_node_test(ctx, child, test)) {
            xpath_nodeset_add(result, child);
        }
    }

    return result;
}

/* descendant:: axis */
static XPathNodeSet* axis_descendant(XPathContext* ctx, struct taurus_element* node,
                                    XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node) return result;
    collect_descendants(ctx, node, result, test);
    return result;
}

/* descendant-or-self:: axis */
static XPathNodeSet* axis_descendant_or_self(XPathContext* ctx,
                                            struct taurus_element* node,
                                            XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node) return result;
    collect_descendants_or_self(ctx, node, result, test);
    return result;
}

/* parent:: axis */
static XPathNodeSet* axis_parent(XPathContext* ctx, struct taurus_element* node,
                                XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node || !node->parent) return result;

    if (matches_node_test(ctx, node->parent, test)) {
        xpath_nodeset_add(result, node->parent);
    }

    return result;
}

/* ancestor:: axis */
static XPathNodeSet* axis_ancestor(XPathContext* ctx, struct taurus_element* node,
                                  XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node) return result;

    struct taurus_element* current = node->parent;
    while (current) {
        if (matches_node_test(ctx, current, test)) {
            xpath_nodeset_add(result, current);
        }
        current = current->parent;
    }

    return result;
}

/* ancestor-or-self:: axis */
static XPathNodeSet* axis_ancestor_or_self(XPathContext* ctx,
                                          struct taurus_element* node,
                                          XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node) return result;

    if (matches_node_test(ctx, node, test)) {
        xpath_nodeset_add(result, node);
    }

    struct taurus_element* current = node->parent;
    while (current) {
        if (matches_node_test(ctx, current, test)) {
            xpath_nodeset_add(result, current);
        }
        current = current->parent;
    }

    return result;
}

/* self:: axis */
static XPathNodeSet* axis_self(XPathContext* ctx, struct taurus_element* node,
                              XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node) return result;

    if (matches_node_test(ctx, node, test)) {
        xpath_nodeset_add(result, node);
    }

    return result;
}

/* following-sibling:: axis */
static XPathNodeSet* axis_following_sibling(XPathContext* ctx,
                                           struct taurus_element* node,
                                           XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node || !node->parent) return result;

    struct taurus_element* parent = node->parent;
    int found = 0;

    for (size_t i = 0; i < parent->children_count; i++) {
        if (parent->children[i] == node) {
            found = 1;
            continue;
        }
        if (found && matches_node_test(ctx, parent->children[i], test)) {
            xpath_nodeset_add(result, parent->children[i]);
        }
    }

    return result;
}

/* preceding-sibling:: axis */
static XPathNodeSet* axis_preceding_sibling(XPathContext* ctx,
                                           struct taurus_element* node,
                                           XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node || !node->parent) return result;

    struct taurus_element* parent = node->parent;

    for (size_t i = 0; i < parent->children_count; i++) {
        if (parent->children[i] == node) break;
        if (matches_node_test(ctx, parent->children[i], test)) {
            xpath_nodeset_add(result, parent->children[i]);
        }
    }

    return result;
}

/* following:: axis - all nodes after context in document order */
static XPathNodeSet* axis_following(XPathContext* ctx, struct taurus_element* node,
                                   XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node || !node->parent) return result;

    /* Get following siblings and their descendants */
    struct taurus_element* parent = node->parent;
    int found = 0;

    for (size_t i = 0; i < parent->children_count; i++) {
        if (parent->children[i] == node) {
            found = 1;
            continue;
        }
        if (found) {
            if (matches_node_test(ctx, parent->children[i], test)) {
                xpath_nodeset_add(result, parent->children[i]);
            }
            collect_descendants(ctx, parent->children[i], result, test);
        }
    }

    /* Recursively get parent's following nodes */
    XPathNodeSet* parent_following = axis_following(ctx, parent, test);
    if (parent_following) {
        for (size_t i = 0; i < xpath_nodeset_count(parent_following); i++) {
            xpath_nodeset_add(result, xpath_nodeset_get(parent_following, i));
        }
        xpath_nodeset_free(parent_following);
    }

    return result;
}

/* preceding:: axis - all nodes before context in document order */
static XPathNodeSet* axis_preceding(XPathContext* ctx, struct taurus_element* node,
                                   XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node || !node->parent) return result;

    /* Get preceding siblings and their descendants */
    struct taurus_element* parent = node->parent;

    for (size_t i = 0; i < parent->children_count; i++) {
        if (parent->children[i] == node) break;
        if (matches_node_test(ctx, parent->children[i], test)) {
            xpath_nodeset_add(result, parent->children[i]);
        }
        collect_descendants(ctx, parent->children[i], result, test);
    }

    /* Recursively get parent's preceding nodes */
    XPathNodeSet* parent_preceding = axis_preceding(ctx, parent, test);
    if (parent_preceding) {
        for (size_t i = 0; i < xpath_nodeset_count(parent_preceding); i++) {
            xpath_nodeset_add(result, xpath_nodeset_get(parent_preceding, i));
        }
        xpath_nodeset_free(parent_preceding);
    }

    return result;
}

/* attribute:: axis
 *
 * Returns attributes as proper TaurusAttributeNode structures.
 * These nodes have type TAURUS_NODE_ATTRIBUTE and work with all
 * type conversion functions properly.
 */
static XPathNodeSet* axis_attribute(XPathContext* ctx, struct taurus_element* node,
                                   XPathASTNode* test) {
    DEBUG_LOG("        === axis_attribute START ===");
    DEBUG_LOG("        node=%p, name=%s", (void*)node, node ? node->name : "(null)");
    DEBUG_LOG("        attributes_count=%zu", node ? (size_t)node->attributes_count : 0);

    XPathNodeSet* result = xpath_nodeset_new();
    if (!result || !node) {
        DEBUG_LOG("        EARLY RETURN: result=%p, node=%p", (void*)result, (void*)node);
        return result;
    }

    /* Iterate through element's attributes */
    for (size_t i = 0; i < node->attributes_count; i++) {
        struct taurus_attribute* attr = node->attributes[i];
        DEBUG_LOG("        [%zu] attr=%p", i, (void*)attr);
        if (!attr) {
            DEBUG_LOG("        [%zu] SKIPPED: attr is NULL", i);
            continue;
        }
        DEBUG_LOG("        [%zu] attr->name=%s, attr->value=%s",
                 i, attr->name ? attr->name : "(null)",
                 attr->value ? attr->value : "(null)");

        /* Check if attribute matches node test */
        int matches = 0;
        if (test && test->type == XPATH_AST_NODE_TEST_NAME) {
            /* Specific attribute name test */
            matches = (test->value && attr->name && strcmp(test->value, attr->name) == 0);
            DEBUG_LOG("        [%zu] NAME test: looking for '%s', matches=%d",
                     i, test->value ? test->value : "(null)", matches);
        } else if (test && test->type == XPATH_AST_NODE_TEST_ALL) {
            /* Wildcard - matches all attributes */
            matches = 1;
            DEBUG_LOG("        [%zu] WILDCARD test: matches=%d", i, matches);
        } else if (!test) {
            /* No test means match all */
            matches = 1;
            DEBUG_LOG("        [%zu] NO test: matches=%d", i, matches);
        }

        if (matches) {
            /* Create proper attribute node */
            DEBUG_LOG("        [%zu] Creating attribute node...", i);
            TaurusAttributeNode* attr_node = create_attribute_node(attr, node);
            DEBUG_LOG("        [%zu] attr_node=%p", i, (void*)attr_node);
            if (attr_node) {
                DEBUG_LOG("        [%zu] attr_node->node_type=%d (should be 1)",
                         i, (int)attr_node->node_type);
                DEBUG_LOG("        [%zu] attr_node->name=%s",
                         i, attr_node->name ? attr_node->name : "(null)");
                DEBUG_LOG("        [%zu] attr_node->value=%s",
                         i, attr_node->value ? attr_node->value : "(null)");
                DEBUG_LOG("        [%zu] Adding to nodeset...", i);
                xpath_nodeset_add(result, (void*)attr_node);
                DEBUG_LOG("        [%zu] Added. Nodeset count now: %zu",
                         i, xpath_nodeset_count(result));
            } else {
                DEBUG_LOG("        [%zu] FAILED to create attr_node!", i);
            }
        }
    }

    DEBUG_LOG("        Final nodeset count: %zu", xpath_nodeset_count(result));
    DEBUG_LOG("        === axis_attribute END ===");
    return result;
}

/* namespace:: axis */
static XPathNodeSet* axis_namespace(XPathContext* ctx, struct taurus_element* node,
                                   XPathASTNode* test) {
    XPathNodeSet* result = xpath_nodeset_new();
    /* Namespace axis rarely used, stub for now */
    return result;
}

/* Apply axis dispatcher */
static XPathNodeSet* apply_axis(XPathContext* ctx, struct taurus_element* node,
                               const char* axis_name, XPathASTNode* test) {
    DEBUG_LOG("      === apply_axis: %s ===", axis_name ? axis_name : "(null/child)");
    if (!axis_name) {
        DEBUG_LOG("        Using default 'child' axis");
        return axis_child(ctx, node, test);
    }

    if (strcmp(axis_name, "child") == 0) {
        DEBUG_LOG("        Using 'child' axis");
        return axis_child(ctx, node, test);
    }
    if (strcmp(axis_name, "descendant") == 0) {
        DEBUG_LOG("        Using 'descendant' axis");
        return axis_descendant(ctx, node, test);
    }
    if (strcmp(axis_name, "descendant-or-self") == 0) {
        DEBUG_LOG("        Using 'descendant-or-self' axis");
        return axis_descendant_or_self(ctx, node, test);
    }
    if (strcmp(axis_name, "parent") == 0) return axis_parent(ctx, node, test);
    if (strcmp(axis_name, "ancestor") == 0) return axis_ancestor(ctx, node, test);
    if (strcmp(axis_name, "ancestor-or-self") == 0)
        return axis_ancestor_or_self(ctx, node, test);
    if (strcmp(axis_name, "self") == 0) return axis_self(ctx, node, test);
    if (strcmp(axis_name, "following-sibling") == 0)
        return axis_following_sibling(ctx, node, test);
    if (strcmp(axis_name, "preceding-sibling") == 0)
        return axis_preceding_sibling(ctx, node, test);
    if (strcmp(axis_name, "following") == 0) return axis_following(ctx, node, test);
    if (strcmp(axis_name, "preceding") == 0) return axis_preceding(ctx, node, test);
    if (strcmp(axis_name, "attribute") == 0) return axis_attribute(ctx, node, test);
    if (strcmp(axis_name, "namespace") == 0) return axis_namespace(ctx, node, test);

    return xpath_nodeset_new();  /* Unknown axis */
}

/* ============================================================================
 * Operator Evaluation
 * ============================================================================ */

static struct taurus_xpath_result* evaluate_operator(XPathContext* ctx,
                                                    XPathASTNode* ast) {
    if (!ast || ast->child_count < 1) return NULL;

    XPathOperatorType op = (XPathOperatorType)ast->number_value;

    /* Unary negation */
    if (op == XPATH_OP_NEGATION) {
        struct taurus_xpath_result* operand = evaluate_expr(ctx, ast->children[0]);
        if (!operand) return NULL;
        double value = xpath_to_number(operand);
        xpath_result_free(operand);

        struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
        if (result) result->value.number_value = -value;
        return result;
    }

    /* Binary operators require 2 operands */
    if (ast->child_count < 2) return NULL;

    struct taurus_xpath_result* left = evaluate_expr(ctx, ast->children[0]);
    if (!left) return NULL;

    /* Short-circuit for logical operators */
    if (op == XPATH_OP_AND) {
        if (!xpath_to_boolean(left)) {
            xpath_result_free(left);
            struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_BOOLEAN);
            if (result) result->value.boolean_value = 0;
            return result;
        }
    } else if (op == XPATH_OP_OR) {
        if (xpath_to_boolean(left)) {
            xpath_result_free(left);
            struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_BOOLEAN);
            if (result) result->value.boolean_value = 1;
            return result;
        }
    }

    struct taurus_xpath_result* right = evaluate_expr(ctx, ast->children[1]);
    if (!right) {
        xpath_result_free(left);
        return NULL;
    }

    struct taurus_xpath_result* result = NULL;

    /* Arithmetic operators */
    if (op == XPATH_OP_PLUS || op == XPATH_OP_MINUS || op == XPATH_OP_MULTIPLY ||
        op == XPATH_OP_DIV || op == XPATH_OP_MOD) {
        double lval = xpath_to_number(left);
        double rval = xpath_to_number(right);
        result = xpath_result_new(XPATH_RESULT_NUMBER);
        if (result) {
            switch (op) {
                case XPATH_OP_PLUS: result->value.number_value = lval + rval; break;
                case XPATH_OP_MINUS: result->value.number_value = lval - rval; break;
                case XPATH_OP_MULTIPLY: result->value.number_value = lval * rval; break;
                case XPATH_OP_DIV: result->value.number_value = lval / rval; break;
                case XPATH_OP_MOD: result->value.number_value = fmod(lval, rval); break;
                default: break;
            }
        }
    }
    /* Comparison operators */
    else if (op >= XPATH_OP_EQUAL && op <= XPATH_OP_GREATER_EQUAL) {
        result = xpath_result_new(XPATH_RESULT_BOOLEAN);
        if (result) {
            /* XPath spec: if both operands are strings, compare as strings */
            if (left->type == XPATH_RESULT_STRING && right->type == XPATH_RESULT_STRING) {
                /* String comparison */
                const char* lstr = left->value.string_value ? left->value.string_value : "";
                const char* rstr = right->value.string_value ? right->value.string_value : "";
                int cmp = strcmp(lstr, rstr);

                switch (op) {
                    case XPATH_OP_EQUAL: result->value.boolean_value = (cmp == 0); break;
                    case XPATH_OP_NOT_EQUAL: result->value.boolean_value = (cmp != 0); break;
                    case XPATH_OP_LESS: result->value.boolean_value = (cmp < 0); break;
                    case XPATH_OP_LESS_EQUAL: result->value.boolean_value = (cmp <= 0); break;
                    case XPATH_OP_GREATER: result->value.boolean_value = (cmp > 0); break;
                    case XPATH_OP_GREATER_EQUAL: result->value.boolean_value = (cmp >= 0); break;
                    default: break;
                }
            } else {
                /* Numeric comparison (default for mixed types) */
                double lval = xpath_to_number(left);
                double rval = xpath_to_number(right);
                switch (op) {
                    case XPATH_OP_EQUAL: result->value.boolean_value = (lval == rval); break;
                    case XPATH_OP_NOT_EQUAL: result->value.boolean_value = (lval != rval); break;
                    case XPATH_OP_LESS: result->value.boolean_value = (lval < rval); break;
                    case XPATH_OP_LESS_EQUAL: result->value.boolean_value = (lval <= rval); break;
                    case XPATH_OP_GREATER: result->value.boolean_value = (lval > rval); break;
                    case XPATH_OP_GREATER_EQUAL: result->value.boolean_value = (lval >= rval); break;
                    default: break;
                }
            }
        }
    }
    /* Logical operators */
    else if (op == XPATH_OP_AND || op == XPATH_OP_OR) {
        int lbool = xpath_to_boolean(left);
        int rbool = xpath_to_boolean(right);
        result = xpath_result_new(XPATH_RESULT_BOOLEAN);
        if (result) {
            result->value.boolean_value = (op == XPATH_OP_AND) ? (lbool && rbool) : (lbool || rbool);
        }
    }
    /* Union operator */
    else if (op == XPATH_OP_UNION) {
        if (left->type != XPATH_RESULT_NODESET || right->type != XPATH_RESULT_NODESET) {
            xpath_result_free(left);
            xpath_result_free(right);
            return NULL;
        }
        result = xpath_result_new(XPATH_RESULT_NODESET);
        if (result) {
            XPathNodeSet* ns = xpath_nodeset_new();
            /* Add left nodes */
            for (size_t i = 0; i < xpath_nodeset_count(left->value.nodeset_value); i++) {
                xpath_nodeset_add(ns, xpath_nodeset_get(left->value.nodeset_value, i));
            }
            /* Add right nodes (skip duplicates) */
            for (size_t i = 0; i < xpath_nodeset_count(right->value.nodeset_value); i++) {
                struct taurus_element* node = xpath_nodeset_get(right->value.nodeset_value, i);
                int duplicate = 0;
                for (size_t j = 0; j < xpath_nodeset_count(ns); j++) {
                    if (xpath_nodeset_get(ns, j) == node) {
                        duplicate = 1;
                        break;
                    }
                }
                if (!duplicate) xpath_nodeset_add(ns, node);
            }
            result->value.nodeset_value = ns;
        }
    }

    xpath_result_free(left);
    xpath_result_free(right);
    return result;
}

/* ============================================================================
 * Predicate Evaluation
 * ============================================================================ */

static XPathNodeSet* apply_predicates(XPathContext* ctx, XPathNodeSet* nodes,
                                     XPathASTNode** predicates, size_t pred_count) {
    if (!nodes || pred_count == 0) return nodes;

    DEBUG_LOG("    === apply_predicates: pred_count=%zu, nodeset size=%zu ===",
             pred_count, xpath_nodeset_count(nodes));

    XPathNodeSet* result = nodes;

    for (size_t p = 0; p < pred_count; p++) {
        DEBUG_LOG("      Processing predicate %zu", p);
        XPathNodeSet* filtered = xpath_nodeset_new();
        if (!filtered) {
            DEBUG_LOG("      FAILED to create filtered nodeset");
            break;
        }

        size_t size = xpath_nodeset_count(result);
        DEBUG_LOG("      Filtering %zu nodes", size);

        for (size_t i = 0; i < size; i++) {
            void* node = xpath_nodeset_get(result, i);

            /* For predicates, we need element context - attributes predicate on their owner */
            struct taurus_element* context_elem = node_as_element(node);
            if (!context_elem) {
                TaurusAttributeNode* attr_node = node_as_attribute(node);
                if (attr_node) {
                    context_elem = attr_node->owner;
                }
            }

            if (!context_elem) {
                DEBUG_LOG("        Node[%zu]: No valid context element, skipping", i);
                continue; /* Skip if no valid context */
            }

            DEBUG_LOG("        Node[%zu]: context_elem=%p (name=%s)",
                     i, (void*)context_elem, context_elem->name ? context_elem->name : "(null)");

            /* Save context */
            struct taurus_element* old_node = ctx->context_node;
            size_t old_pos = ctx->context_position;
            size_t old_size = ctx->context_size;

            ctx->context_node = context_elem;
            ctx->context_position = i + 1;  /* 1-based */
            ctx->context_size = size;

            DEBUG_LOG("        Evaluating predicate with context pos=%zu, size=%zu",
                     ctx->context_position, ctx->context_size);

            /* Evaluate predicate */
            struct taurus_xpath_result* pred_result = evaluate_expr(ctx, predicates[p]);

            /* Restore context */
            ctx->context_node = old_node;
            ctx->context_position = old_pos;
            ctx->context_size = old_size;

            if (pred_result) {
                DEBUG_LOG("        Predicate result type=%d", pred_result->type);
                /* Numeric predicate: matches position */
                if (pred_result->type == XPATH_RESULT_NUMBER) {
                    DEBUG_LOG("          Number=%f, position=%zu",
                             pred_result->value.number_value, i + 1);
                    if ((size_t)pred_result->value.number_value == i + 1) {
                        DEBUG_LOG("          MATCH! Adding node");
                        xpath_nodeset_add(filtered, node);
                    }
                }
                /* Boolean predicate */
                else if (xpath_to_boolean(pred_result)) {
                    DEBUG_LOG("          Boolean=true, adding node");
                    xpath_nodeset_add(filtered, node);
                }
                xpath_result_free(pred_result);
            } else {
                DEBUG_LOG("        Predicate evaluation returned NULL! Error: %s",
                         ctx->error_msg[0] ? ctx->error_msg : "(no error)");
            }
        }

        DEBUG_LOG("      Filtered nodeset size: %zu", xpath_nodeset_count(filtered));
        if (result != nodes) xpath_nodeset_free(result);
        result = filtered;
    }

    DEBUG_LOG("    === apply_predicates END: result size=%zu ===",
             xpath_nodeset_count(result));
    return result;
}

/* ============================================================================
 * Path Expression Evaluation
 * ============================================================================ */

static struct taurus_xpath_result* evaluate_step(XPathContext* ctx,
                                                 XPathASTNode* step,
                                                 XPathNodeSet* input) {
    DEBUG_LOG("  === evaluate_step START ===");
    if (!step || step->type != XPATH_AST_STEP || !input) {
        DEBUG_LOG("    Invalid parameters: step=%p, type=%d, input=%p",
                 (void*)step, step ? step->type : -1, (void*)input);
        return NULL;
    }

    const char* axis_name = step->value ? step->value : "child";
    XPathASTNode* node_test = (step->child_count > 0) ? step->children[0] : NULL;

    DEBUG_LOG("    axis_name = %s", axis_name);
    DEBUG_LOG("    node_test = %p (type=%d)", (void*)node_test, node_test ? node_test->type : -1);
    if (node_test && node_test->value) {
        DEBUG_LOG("    node_test->value = %s", node_test->value);
    }
    DEBUG_LOG("    input nodeset count = %zu", xpath_nodeset_count(input));

    XPathNodeSet* result = xpath_nodeset_new();
    if (!result) {
        DEBUG_LOG("    FAILED to create result nodeset");
        return NULL;
    }

    /* Apply axis to each input node (must be elements) */
    for (size_t i = 0; i < xpath_nodeset_count(input); i++) {
        void* node_ptr = xpath_nodeset_get(input, i);
        struct taurus_element* node = node_as_element(node_ptr);
        DEBUG_LOG("    Processing input[%zu]: node=%p", i, (void*)node);
        if (!node) {
            DEBUG_LOG("      Skipping non-element node");
            continue; /* Skip non-element nodes */
        }
        DEBUG_LOG("      node->name = %s, children_count = %zu",
                 node->name ? node->name : "(null)", node->children_count);

        XPathNodeSet* axis_result = apply_axis(ctx, node, axis_name, node_test);
        DEBUG_LOG("      axis_result count = %zu", axis_result ? xpath_nodeset_count(axis_result) : 0);

        if (axis_result) {
            /* Apply predicates if present */
            XPathNodeSet* filtered = axis_result;
            if (step->child_count > 1) {
                filtered = apply_predicates(ctx, axis_result,
                                           &step->children[1],
                                           step->child_count - 1);
            }

            /* Transfer nodes to result (result will own the attribute nodes) */
            for (size_t j = 0; j < xpath_nodeset_count(filtered); j++) {
                xpath_nodeset_add(result, xpath_nodeset_get(filtered, j));
            }

            /* Don't free attribute nodes from intermediate node sets - result now owns them */
            if (filtered != axis_result) {
                filtered->owns_attributes = 0;
                xpath_nodeset_free(filtered);
            }
            axis_result->owns_attributes = 0;  /* Result nodeset now owns the attributes */
            xpath_nodeset_free(axis_result);
        }
    }

    DEBUG_LOG("    Final result count = %zu", xpath_nodeset_count(result));
    DEBUG_LOG("  === evaluate_step END ===");

    struct taurus_xpath_result* res = xpath_result_new(XPATH_RESULT_NODESET);
    if (res) res->value.nodeset_value = result;
    return res;
}

static struct taurus_xpath_result* evaluate_location_path(XPathContext* ctx,
                                                          XPathASTNode* path) {
    XPathNodeSet* current = xpath_nodeset_new();
    if (!current) return NULL;

    /* Starting nodeset */
    if (path->type == XPATH_AST_ABSOLUTE_PATH) {
        /* Special case: Absolute path with element name as first step
         * XPath "/root" means "child of document node named root"
         * Since we don't have a document node, check if root matches and use it */
        int is_root_match = 0;
        struct taurus_element* root = ctx->document->root;

        DEBUG_LOG("  Checking for special case: child_count=%zu, root=%p",
                 (size_t)path->child_count, (void*)root);

        if (path->child_count > 0 && root && root->name) {
            XPathASTNode* first_child = path->children[0];

            DEBUG_LOG("  First child type=%d (RELATIVE_PATH=%d, STEP=%d)",
                     first_child->type, XPATH_AST_RELATIVE_PATH, XPATH_AST_STEP);

            /* The first child might be RELATIVE_PATH containing steps, or a direct STEP */
            XPathASTNode* first_step = NULL;
            if (first_child->type == XPATH_AST_RELATIVE_PATH && first_child->child_count > 0) {
                first_step = first_child->children[0];
                DEBUG_LOG("  Found RELATIVE_PATH, extracting first step");
            } else if (first_child->type == XPATH_AST_STEP) {
                first_step = first_child;
                DEBUG_LOG("  Found direct STEP");
            }

            /* Check if first step is a simple child axis with element name */
            if (first_step && first_step->type == XPATH_AST_STEP) {
                const char* axis = first_step->value ? first_step->value : "child";
                DEBUG_LOG("  Axis=%s, child_count=%zu", axis, (size_t)first_step->child_count);

                if (strcmp(axis, "child") == 0 && first_step->child_count > 0) {
                    XPathASTNode* node_test = first_step->children[0];
                    DEBUG_LOG("  Node test type=%d, value=%s",
                             node_test->type, node_test->value ? node_test->value : "(null)");

                    if (node_test->type == XPATH_AST_NODE_TEST_NAME && node_test->value) {
                        /* Extract local name from root (strip namespace prefix if present) */
                        const char* root_local = root->name;
                        const char* colon = strchr(root->name, ':');
                        if (colon) root_local = colon + 1;

                        DEBUG_LOG("  Comparing root_local='%s' with node_test='%s'",
                                 root_local, node_test->value);

                        /* Check if root element name matches */
                        if (strcmp(root_local, node_test->value) == 0) {
                            is_root_match = 1;
                            DEBUG_LOG("  ✓ Special case: /root matches document root");
                        }
                    }
                }
            }
        }

        DEBUG_LOG("  is_root_match=%d", is_root_match);

        if (is_root_match) {
            /* Root matches - add it and process remaining steps
             * Structure can be:
             *   /root/child:  ABSOLUTE_PATH → RELATIVE_PATH → [STEP:child::root, STEP:child::child]
             *   /root:        ABSOLUTE_PATH → RELATIVE_PATH → [STEP:child::root]
             */
            xpath_nodeset_add(current, root);
            DEBUG_LOG("  Added root to nodeset, processing remaining steps");

            /* Get the RELATIVE_PATH (first child of ABSOLUTE_PATH) */
            XPathASTNode* rel_path = path->children[0];
            if (rel_path && rel_path->type == XPATH_AST_RELATIVE_PATH && rel_path->child_count > 1) {
                /* Process steps starting from index 1 (skip first step which matched root) */
                for (size_t j = 1; j < rel_path->child_count; j++) {
                    XPathASTNode* step = rel_path->children[j];
                    if (step->type == XPATH_AST_STEP) {
                        DEBUG_LOG("    Processing remaining step %zu", j);
                        struct taurus_xpath_result* step_result = evaluate_step(ctx, step, current);
                        if (!step_result) {
                            xpath_nodeset_free(current);
                            return NULL;
                        }
                        xpath_nodeset_free(current);
                        current = step_result->value.nodeset_value;
                        step_result->value.nodeset_value = NULL;
                        xpath_result_free(step_result);
                    }
                }
            }
            /* If rel_path has only 1 child (the step that matched), we're done - just return root */
        } else {
            /* Normal absolute path - start from root and process ALL steps */
            DEBUG_LOG("  Adding root to initial nodeset for absolute path");
            xpath_nodeset_add(current, ctx->document->root);
            DEBUG_LOG("  Nodeset count after adding root: %zu", xpath_nodeset_count(current));

            /* Process steps - handle both direct steps and those in RELATIVE_PATH */
            DEBUG_LOG("  Processing %zu children", (size_t)path->child_count);
            for (size_t i = 0; i < path->child_count; i++) {
                XPathASTNode* child = path->children[i];
                DEBUG_LOG("  Child[%zu]: type=%d", i, child->type);

                if (child->type == XPATH_AST_STEP) {
                    DEBUG_LOG("    Processing STEP child");
                    DEBUG_LOG("    Input nodeset count: %zu", xpath_nodeset_count(current));
                    /* Direct step child - process it */
                    struct taurus_xpath_result* step_result = evaluate_step(ctx, child, current);
                    if (!step_result) {
                        DEBUG_LOG("    STEP evaluation FAILED");
                        xpath_nodeset_free(current);
                        return NULL;
                    }
                    DEBUG_LOG("    STEP result nodeset count: %zu",
                             xpath_nodeset_count(step_result->value.nodeset_value));

                    xpath_nodeset_free(current);
                    current = step_result->value.nodeset_value;
                    step_result->value.nodeset_value = NULL;
                    xpath_result_free(step_result);
                    DEBUG_LOG("    Current nodeset count: %zu", xpath_nodeset_count(current));
                }
                else if (child->type == XPATH_AST_RELATIVE_PATH) {
                    /* RELATIVE_PATH container - process its step children */
                    for (size_t j = 0; j < child->child_count; j++) {
                        XPathASTNode* step = child->children[j];

                        if (step->type == XPATH_AST_STEP) {
                            struct taurus_xpath_result* step_result = evaluate_step(ctx, step, current);
                            if (!step_result) {
                                xpath_nodeset_free(current);
                                return NULL;
                            }

                            xpath_nodeset_free(current);
                            current = step_result->value.nodeset_value;
                            step_result->value.nodeset_value = NULL;
                            xpath_result_free(step_result);
                        }
                    }
                }
            }
        }
    }  /* End of if (path->type == XPATH_AST_ABSOLUTE_PATH) */
    else {
        /* Relative path - start from context node */
        xpath_nodeset_add(current, ctx->context_node);

        /* Process steps - handle both direct steps and those in RELATIVE_PATH */
        for (size_t i = 0; i < path->child_count; i++) {
            XPathASTNode* child = path->children[i];

            if (child->type == XPATH_AST_STEP) {
                /* Direct step child - process it */
                struct taurus_xpath_result* step_result = evaluate_step(ctx, child, current);
                if (!step_result) {
                    xpath_nodeset_free(current);
                    return NULL;
                }

                xpath_nodeset_free(current);
                current = step_result->value.nodeset_value;
                step_result->value.nodeset_value = NULL;
                xpath_result_free(step_result);
            }
            else if (child->type == XPATH_AST_RELATIVE_PATH) {
                /* RELATIVE_PATH container - process its step children */
                for (size_t j = 0; j < child->child_count; j++) {
                    XPathASTNode* step = child->children[j];

                    if (step->type == XPATH_AST_STEP) {
                        struct taurus_xpath_result* step_result = evaluate_step(ctx, step, current);
                        if (!step_result) {
                            xpath_nodeset_free(current);
                            return NULL;
                        }

                        xpath_nodeset_free(current);
                        current = step_result->value.nodeset_value;
                        step_result->value.nodeset_value = NULL;
                        xpath_result_free(step_result);
                    }
                }
            }
        }
    }

    DEBUG_LOG("  Final nodeset count: %zu", xpath_nodeset_count(current));
    DEBUG_LOG("=== evaluate_location_path END ===");

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NODESET);
    if (result) result->value.nodeset_value = current;
    return result;
}

/* ============================================================================
 * Main Evaluation Dispatcher
 * ============================================================================ */

/* Forward declaration for function call evaluation */
static struct taurus_xpath_result* evaluate_function_call(XPathContext* ctx,
                                                          XPathASTNode* ast);

static struct taurus_xpath_result* evaluate_expr(XPathContext* ctx, XPathASTNode* ast) {
    if (!ctx || !ast) return NULL;

    switch (ast->type) {
        case XPATH_AST_NUMBER: {
            struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
            if (result) result->value.number_value = ast->number_value;
            return result;
        }

        case XPATH_AST_STRING: {
            struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
            if (result) result->value.string_value = taurus_strdup(ast->value ? ast->value : "");
            return result;
        }

        case XPATH_AST_OPERATOR:
            return evaluate_operator(ctx, ast);

        case XPATH_AST_FUNCTION_CALL:
            return evaluate_function_call(ctx, ast);

        case XPATH_AST_PATH_EXPR:
        case XPATH_AST_ABSOLUTE_PATH:
        case XPATH_AST_RELATIVE_PATH:
            return evaluate_location_path(ctx, ast);

        case XPATH_AST_STEP: {
            XPathNodeSet* initial = xpath_nodeset_new();
            if (initial) xpath_nodeset_add(initial, ctx->context_node);
            struct taurus_xpath_result* result = evaluate_step(ctx, ast, initial);
            xpath_nodeset_free(initial);
            return result;
        }

        default: {
            char msg[256];
            snprintf(msg, sizeof(msg), "Unsupported AST node type: %d", ast->type);
            snprintf(ctx->error_msg, sizeof(ctx->error_msg), "%s", msg);

            if (ctx->input) {
                taurus_set_error_with_context(
                    TAURUS_ERROR_EVAL_CONTEXT,
                    msg,
                    ctx->input,
                    0,  /* No specific position for AST node type errors */
                    1, 1
                );
            }
            return NULL;
        }
    }
}

/* ============================================================================
 * Function Call Evaluation
 * ============================================================================ */

/* Helper: Find similar function name (simple Levenshtein distance check) */
static const char* suggest_similar_function(const char* name) {
    if (!name) return NULL;

    /* All XPath 1.0 functions */
    static const char* functions[] = {
        "last", "position", "count", "id", "local-name", "namespace-uri", "name",
        "string", "concat", "starts-with", "contains", "substring-before",
        "substring-after", "substring", "string-length", "normalize-space", "translate",
        "boolean", "not", "true", "false", "lang",
        "number", "sum", "floor", "ceiling", "round",
        NULL
    };

    size_t name_len = strlen(name);
    const char* best_match = NULL;
    int best_distance = 999;

    for (int i = 0; functions[i]; i++) {
        const char* func = functions[i];
        size_t func_len = strlen(func);

        /* Quick filters */
        if (name_len == 0 || func_len == 0) continue;

        /* Check prefix match */
        if (strncmp(name, func, name_len < func_len ? name_len : func_len) == 0) {
            return func;  /* Strong prefix match */
        }

        /* Simple distance: count character differences */
        int distance = abs((int)name_len - (int)func_len);
        for (size_t j = 0; j < (name_len < func_len ? name_len : func_len); j++) {
            if (name[j] != func[j]) distance++;
        }

        /* Only suggest if reasonably close (within 3 edits) */
        if (distance < best_distance && distance <= 3) {
            best_distance = distance;
            best_match = func;
        }
    }

    return best_match;
}

static struct taurus_xpath_result* evaluate_function_call(XPathContext* ctx,
                                                          XPathASTNode* ast) {
    if (!ctx || !ast || !ast->value) {
        if (ctx) {
            char msg[] = "Invalid function call";
            snprintf(ctx->error_msg, sizeof(ctx->error_msg), "%s", msg);
            if (ctx->input) {
                taurus_set_error_with_context(
                    TAURUS_ERROR_XPATH_FUNCTION,
                    msg, ctx->input, 0, 1, 1
                );
            }
        }
        return NULL;
    }

    /* Get function name */
    const char* function_name = ast->value;

    /* Look up function in registry */
    XPathFunctionRegistry* registry = (XPathFunctionRegistry*)ctx->function_registry;
    if (!registry) {
        char msg[] = "Function registry not initialized";
        snprintf(ctx->error_msg, sizeof(ctx->error_msg), "%s", msg);
        if (ctx->input) {
            taurus_set_error_with_context(
                TAURUS_ERROR_XPATH_FUNCTION,
                msg, ctx->input, 0, 1, 1
            );
        }
        return NULL;
    }

    XPathFunctionDef* func_def = xpath_function_registry_get(registry, function_name);
    if (!func_def) {
        /* Try to suggest similar function */
        const char* suggestion = suggest_similar_function(function_name);
        char msg[256];

        if (suggestion) {
            snprintf(msg, sizeof(msg),
                    "Unknown function '%s'. Did you mean '%s'?",
                    function_name, suggestion);
        } else {
            snprintf(msg, sizeof(msg),
                    "Unknown function '%s'", function_name);
        }

        snprintf(ctx->error_msg, sizeof(ctx->error_msg), "%s", msg);

        if (ctx->input) {
            taurus_set_error_with_context(
                TAURUS_ERROR_XPATH_FUNCTION,
                msg, ctx->input, 0, 1, 1
            );
        }
        return NULL;
    }

    /* Validate argument count */
    size_t arg_count = ast->child_count;
    if ((int)arg_count < func_def->min_args) {
        char msg[256];
        snprintf(msg, sizeof(msg),
                "Function '%s()' requires at least %d argument%s, got %zu",
                function_name, func_def->min_args,
                func_def->min_args == 1 ? "" : "s",
                arg_count);
        snprintf(ctx->error_msg, sizeof(ctx->error_msg), "%s", msg);

        if (ctx->input) {
            taurus_set_error_with_context(
                TAURUS_ERROR_XPATH_FUNCTION,
                msg, ctx->input, 0, 1, 1
            );
        }
        return NULL;
    }
    if (func_def->max_args >= 0 && (int)arg_count > func_def->max_args) {
        char msg[256];
        snprintf(msg, sizeof(msg),
                "Function '%s()' accepts at most %d argument%s, got %zu",
                function_name, func_def->max_args,
                func_def->max_args == 1 ? "" : "s",
                arg_count);
        snprintf(ctx->error_msg, sizeof(ctx->error_msg), "%s", msg);

        if (ctx->input) {
            taurus_set_error_with_context(
                TAURUS_ERROR_XPATH_FUNCTION,
                msg, ctx->input, 0, 1, 1
            );
        }
        return NULL;
    }

    /* Call function handler */
    return func_def->handler(ctx, ast->children, arg_count);
}

struct taurus_xpath_result* xpath_evaluate(XPathContext* ctx, XPathASTNode* ast) {
    if (!ctx || !ast) return NULL;
    return evaluate_expr(ctx, ast);
}

/* ============================================================================
 * Public XPath Result API (for libtaurus)
 * ============================================================================ */

/**
 * Evaluate XPath with specific context node
 */
TAURUS_API struct taurus_xpath_result* taurus_xpath_eval_with_context(
    struct taurus_document* doc,
    struct taurus_element* context_node,
    const char* xpath_expr,
    size_t expr_len
) {
    if (!doc || !context_node || !xpath_expr || expr_len == 0) {
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

    /* Create evaluation context with specified context node */
    XPathContext* context = xpath_context_new(doc, context_node);
    if (!context) {
        ast_node_free(ast);
        return NULL;
    }

    /* Store input expression for error reporting (v1.0.0) */
    context->input = xpath_expr;
    context->input_len = expr_len;

    /* Evaluate expression */
    struct taurus_xpath_result* result = xpath_evaluate(context, ast);

    /* Cleanup */
    xpath_context_free(context);
    ast_node_free(ast);

    return result;
}

/**
 * Get result type
 */
TAURUS_API taurus_xpath_result_type taurus_xpath_result_get_type(
    const struct taurus_xpath_result* result
) {
    if (!result) return TAURUS_XPATH_NODESET;

    /* Convert internal type to public enum */
    switch (result->type) {
        case XPATH_RESULT_BOOLEAN: return TAURUS_XPATH_BOOLEAN;
        case XPATH_RESULT_NUMBER: return TAURUS_XPATH_NUMBER;
        case XPATH_RESULT_STRING: return TAURUS_XPATH_STRING;
        case XPATH_RESULT_NODESET: return TAURUS_XPATH_NODESET;
        default: return TAURUS_XPATH_NODESET;
    }
}

/**
 * Get boolean value from result
 */
TAURUS_API int taurus_xpath_result_as_boolean(const struct taurus_xpath_result* result) {
    if (!result) return 0;

    /* Use internal conversion function (it's safe to cast away const) */
    return xpath_to_boolean((struct taurus_xpath_result*)result);
}

/**
 * Get number value from result
 */
TAURUS_API double taurus_xpath_result_as_number(const struct taurus_xpath_result* result) {
    if (!result) return NAN;

    /* Use internal conversion function (it's safe to cast away const) */
    return xpath_to_number((struct taurus_xpath_result*)result);
}

/**
 * Get string value from result
 */
TAURUS_API char* taurus_xpath_result_as_string(const struct taurus_xpath_result* result) {
    if (!result) return taurus_strdup("");

    /* Use internal conversion function (it's safe to cast away const) */
    return xpath_to_string((struct taurus_xpath_result*)result);
}

/**
 * Get node-set size
 */
TAURUS_API size_t taurus_xpath_result_nodeset_size(
    const struct taurus_xpath_result* result
) {
    if (!result || result->type != XPATH_RESULT_NODESET) return 0;
    return xpath_nodeset_count(result->value.nodeset_value);
}

/**
 * Get node from node-set (public API - returns elements only)
 *
 * This function filters the internal nodeset to return only element nodes.
 * Attribute nodes are skipped since they cannot be represented as taurus_element*.
 *
 * Note: The Ruby FFI bridge accesses the nodeset directly and can handle
 * attribute nodes correctly by reading their values.
 */
TAURUS_API struct taurus_element* taurus_xpath_result_nodeset_get(
    const struct taurus_xpath_result* result,
    size_t index
) {
    if (!result || result->type != XPATH_RESULT_NODESET) return NULL;

    XPathNodeSet* nodeset = result->value.nodeset_value;
    if (!nodeset) return NULL;

    /* Count only element nodes to map index correctly */
    size_t element_index = 0;
    for (size_t i = 0; i < nodeset->count; i++) {
        void* node = nodeset->nodes[i];
        if (!node) continue;

        TaurusNodeType node_type = XPATH_NODE_TYPE(node);
        if (node_type == TAURUS_NODE_ELEMENT) {
            if (element_index == index) {
                return (struct taurus_element*)node;
            }
            element_index++;
        }
        /* Skip attribute nodes - they can't be returned as taurus_element* */
    }

    return NULL;
}