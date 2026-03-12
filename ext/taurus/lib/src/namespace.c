/* namespace.c - Taurus namespace API implementation
 * Copyright (c) 2024, Ribose Inc.
 *
 * Namespace declaration and resolution functions
 */

#include "taurus/taurus.h"
#include "taurus_internal.h"
#include <string.h>

/* ============================================================================
 * Element Namespace Declaration Functions
 * ============================================================================ */

/**
 * Get number of namespace declarations
 */
TAURUS_API size_t taurus_element_namespace_count(struct taurus_element* elem) {
    if (!elem) return 0;
    return elem->namespaces_count;
}

/**
 * Get namespace declaration by index
 */
TAURUS_API struct taurus_namespace* taurus_element_namespace_decl(
    struct taurus_element* elem,
    size_t index
) {
    if (!elem) return NULL;
    if (index >= elem->namespaces_count) return NULL;
    
    /* Traverse linked list to find the nth namespace */
    struct taurus_namespace* ns = elem->namespaces;
    for (size_t i = 0; i < index && ns; i++) {
        ns = ns->next;
    }
    
    return ns;
}

/**
 * Resolve namespace prefix
 */
TAURUS_API const char* taurus_element_resolve_namespace(
    struct taurus_element* elem,
    const char* prefix
) {
    if (!elem) return NULL;
    
    /* Search up the element tree for matching namespace declaration */
    struct taurus_element* current = elem;
    while (current) {
        /* Check namespaces on this element */
        struct taurus_namespace* ns = current->namespaces;
        while (ns) {
            /* Match prefix (NULL matches default namespace) */
            if (prefix == NULL && ns->prefix == NULL) {
                return ns->uri;
            }
            if (prefix && ns->prefix && strcmp(prefix, ns->prefix) == 0) {
                return ns->uri;
            }
            ns = ns->next;
        }
        
        /* Move up to parent */
        current = current->parent;
    }
    
    return NULL; /* Not found */
}

/* ============================================================================
 * Namespace Property Functions
 * ============================================================================ */

/**
 * Get namespace prefix
 */
TAURUS_API const char* taurus_namespace_prefix(struct taurus_namespace* ns) {
    if (!ns) return NULL;
    return ns->prefix; /* NULL for default namespace */
}

/**
 * Get namespace URI
 */
TAURUS_API const char* taurus_namespace_uri(struct taurus_namespace* ns) {
    if (!ns) return "";
    return ns->uri ? ns->uri : "";
}