/* libtaurus - Memory management implementation
 * Copyright (c) 2024, Ribose Inc.
 * All rights reserved.
 */

#include "taurus_memory.h"
#include <stdlib.h>
#include <string.h>

/* ============================================================================
 * Document Management
 * ============================================================================ */

struct taurus_document* taurus_document_new(void) {
    struct taurus_document* doc = TAURUS_ALLOC(struct taurus_document);
    if (!doc) return NULL;
    
    doc->root = NULL;
    doc->encoding = NULL;
    doc->pis = NULL;
    doc->ref_count = 1;
    
    return doc;
}

void taurus_document_free_internal(struct taurus_document* doc) {
    if (!doc) return;
    
    /* Free root element tree */
    if (doc->root) {
        taurus_element_free_tree(doc->root);
    }
    
    /* Free encoding string */
    if (doc->encoding) {
        free(doc->encoding);
    }
    
    /* Free processing instructions */
    if (doc->pis) {
        taurus_pi_free_chain(doc->pis);
    }
    
    free(doc);
}

/* ============================================================================
 * Element Management
 * ============================================================================ */

struct taurus_element* taurus_element_new(const char* name) {
    if (!name) return NULL;
    
    struct taurus_element* elem = TAURUS_ALLOC(struct taurus_element);
    if (!elem) return NULL;
    
    /* Initialize all fields */
    elem->name = taurus_strdup(name);
    if (!elem->name) {
        free(elem);
        return NULL;
    }
    
    elem->prefix = NULL;
    elem->namespace_uri = NULL;
    elem->parent = NULL;
    elem->children = NULL;
    elem->children_count = 0;
    elem->children_capacity = 0;
    elem->attributes = NULL;
    elem->attributes_count = 0;
    elem->attributes_capacity = 0;
    elem->namespaces = NULL;
    elem->namespaces_count = 0;
    elem->namespaces_capacity = 0;
    elem->text_content = NULL;
    elem->doc_order = -1;
    
    return elem;
}

void taurus_element_free_shallow(struct taurus_element* elem) {
    size_t i;
    
    if (!elem) return;
    
    /* Free strings */
    if (elem->name) free(elem->name);
    if (elem->prefix) free(elem->prefix);
    if (elem->namespace_uri) free(elem->namespace_uri);
    if (elem->text_content) free(elem->text_content);
    
    /* Free attributes */
    if (elem->attributes) {
        for (i = 0; i < elem->attributes_count; i++) {
            taurus_attribute_free(elem->attributes[i]);
        }
        free(elem->attributes);
    }
    
    /* Free namespace chain */
    taurus_namespace_free_chain(elem->namespaces);
    
    /* Free children array (not elements themselves) */
    if (elem->children) {
        free(elem->children);
    }
    
    free(elem);
}

void taurus_element_free_tree(struct taurus_element* elem) {
    size_t i;
    
    if (!elem) return;
    
    /* Recursively free all children first */
    if (elem->children) {
        for (i = 0; i < elem->children_count; i++) {
            taurus_element_free_tree(elem->children[i]);
        }
    }
    
    /* Then free this element */
    taurus_element_free_shallow(elem);
}

int taurus_element_add_child(struct taurus_element* parent, struct taurus_element* child) {
    if (!parent || !child) return -1;
    
    /* Grow array if needed */
    if (parent->children_count >= parent->children_capacity) {
        TAURUS_GROW_ARRAY(parent->children, parent->children_capacity);
        if (!parent->children) return -1;
    }
    
    /* Add child */
    parent->children[parent->children_count++] = child;
    child->parent = parent;
    
    return 0;
}

int taurus_element_add_attribute(struct taurus_element* elem, struct taurus_attribute* attr) {
    if (!elem || !attr) return -1;
    
    /* Grow array if needed */
    if (elem->attributes_count >= elem->attributes_capacity) {
        TAURUS_GROW_ARRAY(elem->attributes, elem->attributes_capacity);
        if (!elem->attributes) return -1;
    }
    
    /* Add attribute */
    elem->attributes[elem->attributes_count++] = attr;
    
    return 0;
}

int taurus_element_add_namespace(struct taurus_element* elem, struct taurus_namespace* ns) {
    if (!elem || !ns) return -1;
    
    /* Add to linked list at head */
    ns->next = elem->namespaces;
    elem->namespaces = ns;
    elem->namespaces_count++;
    
    return 0;
}

/* ============================================================================
 * Attribute Management
 * ============================================================================ */

struct taurus_attribute* taurus_attribute_new(const char* name, const char* value) {
    if (!name) return NULL;
    
    struct taurus_attribute* attr = TAURUS_ALLOC(struct taurus_attribute);
    if (!attr) return NULL;
    
    attr->name = taurus_strdup(name);
    if (!attr->name) {
        free(attr);
        return NULL;
    }
    
    attr->prefix = NULL;
    attr->namespace_uri = NULL;
    attr->value = value ? taurus_strdup(value) : NULL;
    
    if (value && !attr->value) {
        free(attr->name);
        free(attr);
        return NULL;
    }
    
    return attr;
}

void taurus_attribute_free(struct taurus_attribute* attr) {
    if (!attr) return;
    
    if (attr->name) free(attr->name);
    if (attr->prefix) free(attr->prefix);
    if (attr->namespace_uri) free(attr->namespace_uri);
    if (attr->value) free(attr->value);
    
    free(attr);
}

/* ============================================================================
 * Namespace Management
 * ============================================================================ */

struct taurus_namespace* taurus_namespace_new(const char* prefix, const char* uri) {
    if (!uri) return NULL;
    
    struct taurus_namespace* ns = TAURUS_ALLOC(struct taurus_namespace);
    if (!ns) return NULL;
    
    ns->prefix = prefix ? taurus_strdup(prefix) : NULL;
    ns->uri = taurus_strdup(uri);
    ns->next = NULL;
    
    if (!ns->uri || (prefix && !ns->prefix)) {
        if (ns->prefix) free(ns->prefix);
        if (ns->uri) free(ns->uri);
        free(ns);
        return NULL;
    }
    
    return ns;
}

void taurus_namespace_free_single(struct taurus_namespace* ns) {
    if (!ns) return;
    
    if (ns->prefix) free(ns->prefix);
    if (ns->uri) free(ns->uri);
    free(ns);
}

void taurus_namespace_free_chain(struct taurus_namespace* ns) {
    struct taurus_namespace* next;
    
    while (ns) {
        next = ns->next;
        taurus_namespace_free_single(ns);
        ns = next;
    }
}

struct taurus_namespace* taurus_namespace_find(struct taurus_element* elem, const char* prefix) {
    struct taurus_namespace* ns;
    
    if (!elem) return NULL;
    
    /* Search in current element's namespace declarations */
    for (ns = elem->namespaces; ns; ns = ns->next) {
        if (!prefix && !ns->prefix) {
            /* Both NULL (default namespace) */
            return ns;
        }
        if (prefix && ns->prefix && strcmp(prefix, ns->prefix) == 0) {
            /* Matching prefixes */
            return ns;
        }
    }
    
    /* Not found in current element, check parent (inheritance) */
    if (elem->parent) {
        return taurus_namespace_find(elem->parent, prefix);
    }
    
    return NULL;
}

/* ============================================================================
 * XPath Memory Management
 * ============================================================================ */

XPathNodeSet* taurus_xpath_nodeset_new(void) {
    return taurus_xpath_nodeset_new_with_capacity(4);
}

XPathNodeSet* taurus_xpath_nodeset_new_with_capacity(size_t capacity) {
    XPathNodeSet* nodeset = TAURUS_ALLOC(XPathNodeSet);
    if (!nodeset) return NULL;
    
    nodeset->nodes = TAURUS_ALLOC_N(struct taurus_element*, capacity);
    if (!nodeset->nodes) {
        free(nodeset);
        return NULL;
    }
    
    nodeset->count = 0;
    nodeset->capacity = capacity;
    
    return nodeset;
}

int taurus_xpath_nodeset_add(XPathNodeSet* nodeset, struct taurus_element* node) {
    if (!nodeset || !node) return -1;
    
    /* Grow array if needed */
    if (nodeset->count >= nodeset->capacity) {
        size_t new_cap = nodeset->capacity * 2;
        struct taurus_element** new_nodes = TAURUS_REALLOC_N(nodeset->nodes, struct taurus_element*, new_cap);
        if (!new_nodes) return -1;
        
        nodeset->nodes = new_nodes;
        nodeset->capacity = new_cap;
    }
    
    /* Add node */
    nodeset->nodes[nodeset->count++] = node;
    
    return 0;
}

void taurus_xpath_nodeset_free(XPathNodeSet* nodeset) {
    if (!nodeset) return;
    
    if (nodeset->nodes) {
        free(nodeset->nodes);
    }
    
    free(nodeset);
}

struct taurus_xpath_result* taurus_xpath_result_new(XPathResultType type) {
    struct taurus_xpath_result* result = TAURUS_ALLOC(struct taurus_xpath_result);
    if (!result) return NULL;
    
    result->type = type;
    
    /* Initialize value union based on type */
    switch (type) {
        case XPATH_RESULT_BOOLEAN:
            result->value.boolean_value = 0;
            break;
        case XPATH_RESULT_NUMBER:
            result->value.number_value = 0.0;
            break;
        case XPATH_RESULT_STRING:
            result->value.string_value = NULL;
            break;
        case XPATH_RESULT_NODESET:
            result->value.nodeset_value = NULL;
            break;
    }
    
    return result;
}

void taurus_xpath_result_free_internal(struct taurus_xpath_result* result) {
    if (!result) return;
    
    /* Free owned data based on type */
    switch (result->type) {
        case XPATH_RESULT_STRING:
            if (result->value.string_value) {
                free(result->value.string_value);
            }
            break;
        case XPATH_RESULT_NODESET:
            if (result->value.nodeset_value) {
                taurus_xpath_nodeset_free(result->value.nodeset_value);
            }
            break;
        default:
            /* Boolean and number don't own data */
            break;
    }
    
    free(result);
}

/* ============================================================================
 * Processing Instruction Management
 * ============================================================================ */

struct taurus_processing_instruction* taurus_pi_new(const char* target, const char* data) {
    if (!target) return NULL;
    
    struct taurus_processing_instruction* pi = TAURUS_ALLOC(struct taurus_processing_instruction);
    if (!pi) return NULL;
    
    pi->target = taurus_strdup(target);
    if (!pi->target) {
        free(pi);
        return NULL;
    }
    
    pi->data = data ? taurus_strdup(data) : NULL;
    if (data && !pi->data) {
        free(pi->target);
        free(pi);
        return NULL;
    }
    
    pi->next = NULL;
    
    return pi;
}

void taurus_pi_free(struct taurus_processing_instruction* pi) {
    if (!pi) return;
    
    if (pi->target) free(pi->target);
    if (pi->data) free(pi->data);
    
    free(pi);
}

void taurus_pi_free_chain(struct taurus_processing_instruction* pi) {
    struct taurus_processing_instruction* next;
    
    while (pi) {
        next = pi->next;
        taurus_pi_free(pi);
        pi = next;
    }
}