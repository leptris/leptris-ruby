/* element.c - Taurus element API implementation
 * Copyright (c) 2024, Ribose Inc.
 *
 * Element traversal and access functions
 */

#include "taurus/taurus.h"
#include "taurus_internal.h"

/* ============================================================================
 * Element Hierarchy Functions
 * ============================================================================ */

/**
 * Get parent element
 */
TAURUS_API struct taurus_element* taurus_element_parent(struct taurus_element* elem) {
    if (!elem) return NULL;
    return elem->parent;
}

/**
 * Get number of child elements
 */
TAURUS_API size_t taurus_element_child_count(struct taurus_element* elem) {
    if (!elem) return 0;
    return elem->children_count;
}

/**
 * Get child element by index
 */
TAURUS_API struct taurus_element* taurus_element_child(struct taurus_element* elem, size_t index) {
    if (!elem) return NULL;
    if (index >= elem->children_count) return NULL;
    return elem->children[index];
}

/* ============================================================================
 * Element Namespace Functions
 * ============================================================================ */

/**
 * Get element namespace URI
 */
TAURUS_API const char* taurus_element_namespace(struct taurus_element* elem) {
    if (!elem) return NULL;
    return elem->namespace_uri;
}

/**
 * Get element namespace prefix
 */
TAURUS_API const char* taurus_element_prefix(struct taurus_element* elem) {
    if (!elem) return NULL;
    return elem->prefix;
}