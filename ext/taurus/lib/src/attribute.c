/* attribute.c - Taurus attribute API implementation
 * Copyright (c) 2024, Ribose Inc.
 *
 * Attribute access functions
 */

#include "taurus/taurus.h"
#include "taurus_internal.h"
#include <string.h>

/* ============================================================================
 * Element Attribute Access Functions
 * ============================================================================ */

/**
 * Get number of attributes
 */
TAURUS_API size_t taurus_element_attribute_count(struct taurus_element* elem) {
    if (!elem) return 0;
    return elem->attributes_count;
}

/**
 * Get attribute by index
 */
TAURUS_API struct taurus_attribute* taurus_element_attribute(
    struct taurus_element* elem,
    size_t index
) {
    if (!elem) return NULL;
    if (index >= elem->attributes_count) return NULL;
    return elem->attributes[index];
}

/**
 * Get attribute value by name
 */
TAURUS_API const char* taurus_element_get_attribute(
    struct taurus_element* elem,
    const char* name
) {
    if (!elem || !name) return NULL;
    
    /* Search through attributes for matching name */
    for (size_t i = 0; i < elem->attributes_count; i++) {
        struct taurus_attribute* attr = elem->attributes[i];
        if (attr && attr->name && strcmp(attr->name, name) == 0) {
            return attr->value;
        }
    }
    
    return NULL; /* Not found */
}

/**
 * Check if element has attribute
 */
TAURUS_API int taurus_element_has_attribute(
    struct taurus_element* elem,
    const char* name
) {
    if (!elem || !name) return 0;
    
    /* Search through attributes for matching name */
    for (size_t i = 0; i < elem->attributes_count; i++) {
        struct taurus_attribute* attr = elem->attributes[i];
        if (attr && attr->name && strcmp(attr->name, name) == 0) {
            return 1; /* Found */
        }
    }
    
    return 0; /* Not found */
}

/* ============================================================================
 * Attribute Property Functions
 * ============================================================================ */

/**
 * Get attribute name
 */
TAURUS_API const char* taurus_attribute_name(struct taurus_attribute* attr) {
    if (!attr) return "";
    return attr->name ? attr->name : "";
}

/**
 * Get attribute value
 */
TAURUS_API const char* taurus_attribute_value(struct taurus_attribute* attr) {
    if (!attr) return "";
    return attr->value ? attr->value : "";
}

/**
 * Get attribute namespace URI
 */
TAURUS_API const char* taurus_attribute_namespace(struct taurus_attribute* attr) {
    if (!attr) return NULL;
    return attr->namespace_uri;
}