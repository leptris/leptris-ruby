/* functions.c - XPath 1.0 function library implementation
 * Copyright (c) 2024, Ribose Inc.
 *
 * Pure C implementation of all 27 XPath 1.0 standard functions.
 * Converted from Ruby C extension to standalone C library.
 */

#include "functions.h"
#include "evaluator.h"
#include "taurus/taurus.h"
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <ctype.h>
#include <stdio.h>
#include <float.h>
#include <errno.h>

/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

/* External evaluator function */
extern struct taurus_xpath_result* xpath_evaluate(XPathContext* context,
                                                   XPathASTNode* ast);

/* Helper functions */
static char* get_element_text(struct taurus_element* element);
static char* result_to_string(struct taurus_xpath_result* result);
static int result_to_boolean(struct taurus_xpath_result* result);
static double result_to_number(struct taurus_xpath_result* result);

/* UTF-8 helpers */
static size_t utf8_strlen(const char* str);
static size_t utf8_char_offset(const char* str, size_t char_pos);
static char* utf8_substring(const char* str, size_t start_char, size_t char_count);

/* ============================================================================
 * Function Registry Implementation
 * ============================================================================ */

XPathFunctionRegistry* xpath_function_registry_new(void) {
    XPathFunctionRegistry* registry = TAURUS_ALLOC(XPathFunctionRegistry);
    if (!registry) return NULL;

    registry->functions = NULL;
    registry->count = 0;
    registry->capacity = 0;

    return registry;
}

void xpath_function_registry_free(XPathFunctionRegistry* registry) {
    if (!registry) return;

    if (registry->functions) {
        TAURUS_FREE(registry->functions);
    }
    TAURUS_FREE(registry);
}

void xpath_function_registry_register(
    XPathFunctionRegistry* registry,
    const char* name,
    XPathFunctionHandler handler,
    int min_args,
    int max_args
) {
    if (!registry || !name || !handler) return;

    /* Resize if needed */
    if (registry->count >= registry->capacity) {
        size_t new_capacity = registry->capacity == 0 ? 8 : registry->capacity * 2;
        XPathFunctionDef* new_functions = TAURUS_REALLOC_N(
            registry->functions,
            XPathFunctionDef,
            new_capacity
        );
        if (!new_functions) return;
        registry->functions = new_functions;
        registry->capacity = new_capacity;
    }

    /* Add function */
    registry->functions[registry->count].name = name;
    registry->functions[registry->count].handler = handler;
    registry->functions[registry->count].min_args = min_args;
    registry->functions[registry->count].max_args = max_args;
    registry->count++;
}

XPathFunctionHandler xpath_function_registry_lookup(
    XPathFunctionRegistry* registry,
    const char* name
) {
    if (!registry || !name) return NULL;

    for (size_t i = 0; i < registry->count; i++) {
        if (strcmp(registry->functions[i].name, name) == 0) {
            return registry->functions[i].handler;
        }
    }

    return NULL;
}

XPathFunctionDef* xpath_function_registry_get(
    XPathFunctionRegistry* registry,
    const char* name
) {
    if (!registry || !name) return NULL;

    for (size_t i = 0; i < registry->count; i++) {
        if (strcmp(registry->functions[i].name, name) == 0) {
            return &registry->functions[i];
        }
    }

    return NULL;
}

/* ============================================================================
 * Helper Functions for Type Conversion
 * ============================================================================ */

/* Get text content from typed node (handles elements and attributes) */
static char* get_node_text(void* node) {
    if (!node) return taurus_strdup("");

    /* Check if first 4 bytes match TAURUS_NODE_ATTRIBUTE */
    uint32_t first_int = *(uint32_t*)node;

    if (first_int == TAURUS_NODE_ATTRIBUTE) {
        /* It's an attribute node - cast to proper type and read value */
        TaurusAttributeNode* attr = (TaurusAttributeNode*)node;
        return taurus_strdup(attr->value ? attr->value : "");
    }

    /* It's an element node */
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

    /* Recursively collect text from children (children are always elements) */
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

/* Backward compatibility wrapper */
static char* get_element_text(struct taurus_element* element) {
    return get_node_text((void*)element);
}

/* Convert XPath result to string according to XPath 1.0 spec */
static char* result_to_string(struct taurus_xpath_result* result) {
    if (!result) return taurus_strdup("");

    switch (result->type) {
        case XPATH_RESULT_STRING:
            return result->value.string_value ?
                   taurus_strdup(result->value.string_value) : taurus_strdup("");

        case XPATH_RESULT_NUMBER: {
            double num = result->value.number_value;
            char buffer[64];

            /* Handle special values per XPath spec */
            if (isnan(num)) {
                return taurus_strdup("NaN");
            } else if (isinf(num)) {
                return taurus_strdup(num > 0 ? "Infinity" : "-Infinity");
            } else if (num == 0.0) {
                return taurus_strdup("0");
            } else if (num == floor(num)) {
                /* Integer - no decimal point */
                snprintf(buffer, sizeof(buffer), "%.0f", num);
            } else {
                snprintf(buffer, sizeof(buffer), "%g", num);
            }
            return taurus_strdup(buffer);
        }

        case XPATH_RESULT_BOOLEAN:
            return taurus_strdup(result->value.boolean_value ? "true" : "false");

        case XPATH_RESULT_NODESET: {
            /* String value of first node in document order */
            XPathNodeSet* nodeset = result->value.nodeset_value;
            if (!nodeset || xpath_nodeset_count(nodeset) == 0) {
                return taurus_strdup("");
            }
            void* first_node = xpath_nodeset_get(nodeset, 0);
            return get_node_text(first_node);
        }

        default:
            return taurus_strdup("");
    }
}

/* Convert XPath result to boolean according to XPath 1.0 spec */
static int result_to_boolean(struct taurus_xpath_result* result) {
    if (!result) return 0;

    switch (result->type) {
        case XPATH_RESULT_BOOLEAN:
            return result->value.boolean_value;
        case XPATH_RESULT_NUMBER:
            /* Number is false if 0 or NaN */
            return result->value.number_value != 0.0 &&
                   !isnan(result->value.number_value);
        case XPATH_RESULT_STRING:
            /* String is false if empty */
            return result->value.string_value &&
                   result->value.string_value[0] != '\0';
        case XPATH_RESULT_NODESET:
            /* Nodeset is false if empty */
            return xpath_nodeset_count(result->value.nodeset_value) > 0;
        default:
            return 0;
    }
}

/* Convert XPath result to number according to XPath 1.0 spec */
static double result_to_number(struct taurus_xpath_result* result) {
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

            /* Empty string or only whitespace -> NaN */
            if (*str == '\0') return NAN;

            /* Try to parse as number */
            char* endptr;
            double value = strtod(str, &endptr);

            /* Skip trailing whitespace */
            while (isspace((unsigned char)*endptr)) endptr++;

            /* If we didn't consume the entire string (after trimming), it's NaN */
            if (*endptr != '\0') return NAN;

            return value;
        }

        case XPATH_RESULT_NODESET: {
            /* Convert first node's string value to number */
            XPathNodeSet* nodeset = result->value.nodeset_value;
            if (!nodeset || xpath_nodeset_count(nodeset) == 0) {
                return NAN;
            }
            void* first_node = xpath_nodeset_get(nodeset, 0);
            char* str = get_node_text(first_node);

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

            if (*endptr != '\0') {
                TAURUS_FREE(str);
                return NAN;
            }

            TAURUS_FREE(str);
            return value;
        }

        default:
            return NAN;
    }
}

/* ============================================================================
 * UTF-8 Helper Functions
 * ============================================================================ */

/* Count UTF-8 characters (not bytes) in a string */
static size_t utf8_strlen(const char* str) {
    if (!str) return 0;

    size_t count = 0;
    const unsigned char* p = (const unsigned char*)str;

    while (*p) {
        /* Count leading bytes only (not continuation bytes 10xxxxxx) */
        if ((*p & 0xC0) != 0x80) {
            count++;
        }
        p++;
    }

    return count;
}

/* Get byte offset for UTF-8 character at position (0-based character index) */
static size_t utf8_char_offset(const char* str, size_t char_pos) {
    if (!str) return 0;

    size_t count = 0;
    size_t offset = 0;
    const unsigned char* p = (const unsigned char*)str;

    /* Special case: position 0 is offset 0 */
    if (char_pos == 0) return 0;

    while (*p) {
        /* Move to next byte */
        offset++;
        p++;

        /* Check if we've reached a new character (not a continuation byte) */
        if (*p && (*p & 0xC0) != 0x80) {
            count++;
            if (count == char_pos) {
                return offset;
            }
        }
    }

    /* If we've gone past the end, return the string length */
    return offset;
}

/* Extract substring by character positions (0-based character indices) */
static char* utf8_substring(const char* str, size_t start_char, size_t char_count) {
    if (!str || char_count == 0) return taurus_strdup("");

    size_t str_len_chars = utf8_strlen(str);

    /* Clamp start position to valid range */
    if (start_char >= str_len_chars) {
        return taurus_strdup("");
    }

    /* Clamp character count to available characters */
    if (start_char + char_count > str_len_chars) {
        char_count = str_len_chars - start_char;
    }

    /* Get byte offsets */
    size_t start_byte = utf8_char_offset(str, start_char);
    size_t end_char = start_char + char_count;
    size_t end_byte = utf8_char_offset(str, end_char);

    size_t length = end_byte - start_byte;
    if (length == 0) return taurus_strdup("");

    char* result = TAURUS_ALLOC_N(char, length + 1);
    if (!result) return taurus_strdup("");

    memcpy(result, str + start_byte, length);
    result[length] = '\0';

    return result;
}

/* ============================================================================
 * Core XPath 1.0 Functions
 * ============================================================================ */

/* last() - Returns the context size (number of nodes in context nodeset) */
static struct taurus_xpath_result* xpath_func_last(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    (void)args;  /* Unused */

    if (arg_count != 0) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "last() takes no arguments");
        return NULL;
    }

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
    if (!result) return NULL;

    result->value.number_value = (double)context->context_size;
    return result;
}

/* position() - Returns the context position (1-based) */
static struct taurus_xpath_result* xpath_func_position(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    (void)args;  /* Unused */

    if (arg_count != 0) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "position() takes no arguments");
        return NULL;
    }

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
    if (!result) return NULL;

    result->value.number_value = (double)context->context_position;
    return result;
}

/* ============================================================================
 * XPath String Functions
 * ============================================================================ */

/* string(object?) - Convert argument to string */
static struct taurus_xpath_result* xpath_func_string(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
    if (!result) return NULL;

    if (arg_count == 0) {
        /* No argument: convert context node to string */
        result->value.string_value = get_element_text(context->context_node);
    } else {
        /* Evaluate argument and convert to string */
        struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
        if (!arg_result) {
            xpath_result_free(result);
            return NULL;
        }

        result->value.string_value = result_to_string(arg_result);
        xpath_result_free(arg_result);
    }

    return result;
}

/* concat(string, string, string*) - Concatenate strings */
static struct taurus_xpath_result* xpath_func_concat(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count < 2) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "concat() requires at least 2 arguments");
        return NULL;
    }

    /* Calculate total length needed */
    size_t total_length = 0;
    char** strings = TAURUS_ALLOC_N(char*, arg_count);
    if (!strings) return NULL;

    for (size_t i = 0; i < arg_count; i++) {
        struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[i]);
        if (!arg_result) {
            /* Cleanup and return NULL */
            for (size_t j = 0; j < i; j++) {
                TAURUS_FREE(strings[j]);
            }
            TAURUS_FREE(strings);
            return NULL;
        }

        strings[i] = result_to_string(arg_result);
        total_length += strlen(strings[i]);
        xpath_result_free(arg_result);
    }

    /* Allocate result string */
    char* concat_str = TAURUS_ALLOC_N(char, total_length + 1);
    if (!concat_str) {
        for (size_t i = 0; i < arg_count; i++) {
            TAURUS_FREE(strings[i]);
        }
        TAURUS_FREE(strings);
        return NULL;
    }

    /* Concatenate all strings */
    concat_str[0] = '\0';
    for (size_t i = 0; i < arg_count; i++) {
        strcat(concat_str, strings[i]);
        TAURUS_FREE(strings[i]);
    }
    TAURUS_FREE(strings);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
    if (!result) {
        TAURUS_FREE(concat_str);
        return NULL;
    }
    result->value.string_value = concat_str;

    return result;
}

/* starts-with(string, string) - Check if string starts with prefix */
static struct taurus_xpath_result* xpath_func_starts_with(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 2) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "starts-with() requires exactly 2 arguments");
        return NULL;
    }

    struct taurus_xpath_result* str_result = xpath_evaluate(context, args[0]);
    if (!str_result) return NULL;

    struct taurus_xpath_result* prefix_result = xpath_evaluate(context, args[1]);
    if (!prefix_result) {
        xpath_result_free(str_result);
        return NULL;
    }

    char* str = result_to_string(str_result);
    char* prefix = result_to_string(prefix_result);

    int match = (strncmp(str, prefix, strlen(prefix)) == 0);

    TAURUS_FREE(str);
    TAURUS_FREE(prefix);
    xpath_result_free(str_result);
    xpath_result_free(prefix_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_BOOLEAN);
    if (!result) return NULL;
    result->value.boolean_value = match;

    return result;
}

/* contains(string, string) - Check if string contains substring */
static struct taurus_xpath_result* xpath_func_contains(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 2) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "contains() requires exactly 2 arguments");
        return NULL;
    }

    struct taurus_xpath_result* str_result = xpath_evaluate(context, args[0]);
    if (!str_result) return NULL;

    struct taurus_xpath_result* substr_result = xpath_evaluate(context, args[1]);
    if (!substr_result) {
        xpath_result_free(str_result);
        return NULL;
    }

    char* str = result_to_string(str_result);
    char* substr = result_to_string(substr_result);

    int match = (strstr(str, substr) != NULL);

    TAURUS_FREE(str);
    TAURUS_FREE(substr);
    xpath_result_free(str_result);
    xpath_result_free(substr_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_BOOLEAN);
    if (!result) return NULL;
    result->value.boolean_value = match;

    return result;
}

/* substring(string, number, number?) - Extract substring (1-BASED INDEXING!) */
static struct taurus_xpath_result* xpath_func_substring(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count < 2 || arg_count > 3) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "substring() requires 2 or 3 arguments");
        return NULL;
    }

    /* Get string argument */
    struct taurus_xpath_result* str_result = xpath_evaluate(context, args[0]);
    if (!str_result) return NULL;
    char* str = result_to_string(str_result);
    xpath_result_free(str_result);

    /* Get start position (1-based!) */
    struct taurus_xpath_result* start_result = xpath_evaluate(context, args[1]);
    if (!start_result) {
        TAURUS_FREE(str);
        return NULL;
    }

    double start_pos = result_to_number(start_result);
    xpath_result_free(start_result);

    /* Get optional length */
    double length = INFINITY;
    if (arg_count == 3) {
        struct taurus_xpath_result* len_result = xpath_evaluate(context, args[2]);
        if (!len_result) {
            TAURUS_FREE(str);
            return NULL;
        }

        length = result_to_number(len_result);
        xpath_result_free(len_result);
    }

    /* Handle NaN and special values per XPath spec */
    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
    if (!result) {
        TAURUS_FREE(str);
        return NULL;
    }

    if (isnan(start_pos) || isnan(length)) {
        result->value.string_value = taurus_strdup("");
        TAURUS_FREE(str);
        return result;
    }

    /* Round to nearest according to XPath spec */
    start_pos = round(start_pos);
    length = round(length);

    /* v1.1.0: Handle negative or zero start positions per XPath 1.0 spec
     * XPath uses 1-based indexing, so position < 1 is "before the string"
     * Example: substring("12345", 0, 3) covers positions [0, 1, 2]
     *          Only position 1 is valid, so result is "1" */
    if (start_pos < 1.0) {
        /* Adjust length to account for positions before position 1 */
        double chars_before = 1.0 - start_pos;
        length -= chars_before;
        start_pos = 1.0;

        /* If adjusted length is now non-positive, return empty */
        if (length <= 0.0) {
            result->value.string_value = taurus_strdup("");
            TAURUS_FREE(str);
            return result;
        }
    }

    /* XPath substring extracts characters at positions [start_pos, start_pos + length)
     * in 1-based indexing. We need to find the intersection with valid range [1, str_len] */

    size_t str_len = utf8_strlen(str);

    if (length <= 0) {
        result->value.string_value = taurus_strdup("");
        TAURUS_FREE(str);
        return result;
    }

    /* Calculate the range of 1-based positions we want: [start_pos, start_pos + length) */
    double end_pos = start_pos + length;

    /* Intersect with valid range [1, str_len + 1)
     * (end is exclusive, so str_len + 1 is one past the last character) */
    double actual_start_1based = start_pos < 1.0 ? 1.0 : start_pos;
    double actual_end_1based = end_pos > (double)(str_len + 1) ?
                               (double)(str_len + 1) : end_pos;

    /* If no intersection, return empty */
    if (actual_start_1based >= actual_end_1based ||
        actual_start_1based > (double)str_len) {
        result->value.string_value = taurus_strdup("");
        TAURUS_FREE(str);
        return result;
    }

    /* Calculate how many characters to extract */
    size_t actual_length = (size_t)(actual_end_1based - actual_start_1based);

    /* Convert to 0-based for C string indexing */
    size_t actual_start = (size_t)(actual_start_1based - 1);

    /* Extract substring using UTF-8 aware function */
    result->value.string_value = utf8_substring(str, actual_start, actual_length);
    TAURUS_FREE(str);

    return result;
}

/* string-length(string?) - Get character length of string */
static struct taurus_xpath_result* xpath_func_string_length(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    char* str;

    if (arg_count == 0) {
        /* No argument: use context node string value */
        str = get_element_text(context->context_node);
    } else {
        struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
        if (!arg_result) return NULL;
        str = result_to_string(arg_result);
        xpath_result_free(arg_result);
    }

    size_t length = utf8_strlen(str);
    TAURUS_FREE(str);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
    if (!result) return NULL;
    result->value.number_value = (double)length;

    return result;
}

/* normalize-space(string?) - Normalize whitespace */
static struct taurus_xpath_result* xpath_func_normalize_space(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    char* str;

    if (arg_count == 0) {
        /* No argument: use context node string value */
        str = get_element_text(context->context_node);
    } else {
        struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
        if (!arg_result) return NULL;
        str = result_to_string(arg_result);
        xpath_result_free(arg_result);
    }

    /* Allocate buffer for normalized string (can't be longer than original) */
    char* normalized = TAURUS_ALLOC_N(char, strlen(str) + 1);
    if (!normalized) {
        TAURUS_FREE(str);
        return NULL;
    }

    char* out = normalized;
    const char* in = str;
    int in_space = 0;
    int started = 0;

    /* Skip leading whitespace and collapse internal whitespace */
    while (*in) {
        if (isspace((unsigned char)*in)) {
            in_space = 1;
            in++;
        } else {
            if (started && in_space) {
                *out++ = ' ';
            }
            *out++ = *in++;
            in_space = 0;
            started = 1;
        }
    }
    *out = '\0';

    TAURUS_FREE(str);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
    if (!result) {
        TAURUS_FREE(normalized);
        return NULL;
    }
    result->value.string_value = normalized;

    return result;
}

/* ============================================================================
 * XPath Boolean Functions
 * ============================================================================ */

/* boolean(object) - Convert any object to boolean */
static struct taurus_xpath_result* xpath_func_boolean(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "boolean() requires exactly 1 argument");
        return NULL;
    }

    /* Evaluate argument */
    struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
    if (!arg_result) return NULL;

    /* Convert to boolean */
    int bool_value = result_to_boolean(arg_result);
    xpath_result_free(arg_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_BOOLEAN);
    if (!result) return NULL;
    result->value.boolean_value = bool_value;

    return result;
}

/* not(boolean) - Logical negation */
static struct taurus_xpath_result* xpath_func_not(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "not() requires exactly 1 argument");
        return NULL;
    }

    /* Evaluate argument */
    struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
    if (!arg_result) return NULL;

    /* Convert to boolean and negate */
    int bool_value = result_to_boolean(arg_result);
    xpath_result_free(arg_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_BOOLEAN);
    if (!result) return NULL;
    result->value.boolean_value = !bool_value;

    return result;
}

/* true() - Returns boolean true */
static struct taurus_xpath_result* xpath_func_true(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    (void)context;  /* Unused */
    (void)args;     /* Unused */

    if (arg_count != 0) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "true() takes no arguments");
        return NULL;
    }

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_BOOLEAN);
    if (!result) return NULL;
    result->value.boolean_value = 1;

    return result;
}

/* false() - Returns boolean false */
static struct taurus_xpath_result* xpath_func_false(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    (void)context;  /* Unused */
    (void)args;     /* Unused */

    if (arg_count != 0) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "false() takes no arguments");
        return NULL;
    }

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_BOOLEAN);
    if (!result) return NULL;
    result->value.boolean_value = 0;

    return result;
}

/* ============================================================================
 * XPath Number Functions
 * ============================================================================ */

/* number(object?) - Convert argument to number */
static struct taurus_xpath_result* xpath_func_number(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count > 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "number() takes 0 or 1 argument");
        return NULL;
    }

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
    if (!result) return NULL;

    if (arg_count == 0) {
        /* No argument: convert context node to number */
        char* str = get_element_text(context->context_node);
        const char* p = str;
        while (isspace((unsigned char)*p)) p++;

        if (*p == '\0') {
            result->value.number_value = NAN;
        } else {
            char* endptr;
            double value = strtod(p, &endptr);
            while (isspace((unsigned char)*endptr)) endptr++;
            result->value.number_value = (*endptr == '\0') ? value : NAN;
        }
        TAURUS_FREE(str);
    } else {
        /* Evaluate argument and convert to number */
        struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
        if (!arg_result) {
            xpath_result_free(result);
            return NULL;
        }
        result->value.number_value = result_to_number(arg_result);
        xpath_result_free(arg_result);
    }
    return result;
}

/* sum(node-set) - Sum the numeric values of all nodes */
static struct taurus_xpath_result* xpath_func_sum(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "sum() requires exactly 1 argument");
        return NULL;
    }

    struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
    if (!arg_result) return NULL;

    if (arg_result->type != XPATH_RESULT_NODESET) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "sum() argument must be a nodeset");
        xpath_result_free(arg_result);
        return NULL;
    }

    XPathNodeSet* nodeset = arg_result->value.nodeset_value;
    double sum = 0.0;

    if (nodeset) {
        size_t count = xpath_nodeset_count(nodeset);
        for (size_t i = 0; i < count; i++) {
            void* node = xpath_nodeset_get(nodeset, i);
            char* str = get_node_text(node);
            const char* p = str;
            while (isspace((unsigned char)*p)) p++;

            if (*p != '\0') {
                char* endptr;
                double value = strtod(p, &endptr);
                while (isspace((unsigned char)*endptr)) endptr++;
                if (*endptr == '\0' && !isnan(value)) {
                    sum += value;
                }
            }
            TAURUS_FREE(str);
        }
    }
    xpath_result_free(arg_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
    if (!result) return NULL;
    result->value.number_value = sum;
    return result;
}

/* floor(number) - Largest integer not greater than argument */
static struct taurus_xpath_result* xpath_func_floor(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "floor() requires exactly 1 argument");
        return NULL;
    }

    struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
    if (!arg_result) return NULL;

    double num = result_to_number(arg_result);
    xpath_result_free(arg_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
    if (!result) return NULL;
    result->value.number_value = floor(num);
    return result;
}

/* ceiling(number) - Smallest integer not less than argument */
static struct taurus_xpath_result* xpath_func_ceiling(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "ceiling() requires exactly 1 argument");
        return NULL;
    }

    struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
    if (!arg_result) return NULL;

    double num = result_to_number(arg_result);
    xpath_result_free(arg_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
    if (!result) return NULL;
    result->value.number_value = ceil(num);
    return result;
}

/* round(number) - Round to nearest integer (half away from zero) */
static struct taurus_xpath_result* xpath_func_round(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "round() requires exactly 1 argument");
        return NULL;
    }

    struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
    if (!arg_result) return NULL;

    double num = result_to_number(arg_result);
    xpath_result_free(arg_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
    if (!result) return NULL;

    /* XPath round() rounds half away from zero */
    if (isnan(num) || isinf(num) || num == 0.0) {
        result->value.number_value = num;
    } else {
        double frac = num - floor(num);
        if (frac == 0.5) {
            result->value.number_value = (num > 0) ? ceil(num) : floor(num);
        } else {
            result->value.number_value = floor(num + 0.5);
        }
    }
    return result;
}

/* ============================================================================
 * XPath Node-set Functions
 * ============================================================================ */

/* Helper to recursively find elements by id */
static void find_elements_by_id(struct taurus_element* node, const char* id,
                                XPathNodeSet* result) {
    if (!node) return;

    /* Check this node's id attribute */
    for (size_t i = 0; i < node->attributes_count; i++) {
        struct taurus_attribute* attr = node->attributes[i];
        if (attr && attr->name && strcmp(attr->name, "id") == 0) {
            if (attr->value && strcmp(attr->value, id) == 0) {
                xpath_nodeset_add(result, node);
            }
        }
    }

    /* Search children */
    for (size_t i = 0; i < node->children_count; i++) {
        find_elements_by_id(node->children[i], id, result);
    }
}

/* count(node-set) - Returns the number of nodes */
static struct taurus_xpath_result* xpath_func_count(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "count() requires exactly 1 argument");
        return NULL;
    }

    struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
    if (!arg_result) return NULL;

    if (arg_result->type != XPATH_RESULT_NODESET) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "count() argument must be a nodeset");
        xpath_result_free(arg_result);
        return NULL;
    }

    XPathNodeSet* nodeset = arg_result->value.nodeset_value;
    size_t count = nodeset ? xpath_nodeset_count(nodeset) : 0;
    xpath_result_free(arg_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NUMBER);
    if (!result) return NULL;
    result->value.number_value = (double)count;
    return result;
}

/* local-name(node-set?) - Local name of first node */
static struct taurus_xpath_result* xpath_func_local_name(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count > 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "local-name() takes 0 or 1 argument");
        return NULL;
    }

    struct taurus_element* node;
    if (arg_count == 0) {
        node = context->context_node;
    } else {
        struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
        if (!arg_result) return NULL;

        if (arg_result->type != XPATH_RESULT_NODESET) {
            xpath_result_free(arg_result);
            struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
            if (result) result->value.string_value = taurus_strdup("");
            return result;
        }

        XPathNodeSet* nodeset = arg_result->value.nodeset_value;
        if (!nodeset || xpath_nodeset_count(nodeset) == 0) {
            xpath_result_free(arg_result);
            struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
            if (result) result->value.string_value = taurus_strdup("");
            return result;
        }

        node = xpath_nodeset_get(nodeset, 0);
        xpath_result_free(arg_result);
    }

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
    if (!result) return NULL;

    if (!node || !node->name) {
        result->value.string_value = taurus_strdup("");
        return result;
    }

    /* Return local name (after ':' if present) */
    const char* colon = strchr(node->name, ':');
    result->value.string_value = taurus_strdup(colon ? colon + 1 : node->name);
    return result;
}

/* namespace-uri(node-set?) - Namespace URI of first node */
static struct taurus_xpath_result* xpath_func_namespace_uri(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count > 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "namespace-uri() takes 0 or 1 argument");
        return NULL;
    }

    struct taurus_element* node;
    if (arg_count == 0) {
        node = context->context_node;
    } else {
        struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
        if (!arg_result) return NULL;

        if (arg_result->type != XPATH_RESULT_NODESET) {
            xpath_result_free(arg_result);
            struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
            if (result) result->value.string_value = taurus_strdup("");
            return result;
        }

        XPathNodeSet* nodeset = arg_result->value.nodeset_value;
        if (!nodeset || xpath_nodeset_count(nodeset) == 0) {
            xpath_result_free(arg_result);
            struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
            if (result) result->value.string_value = taurus_strdup("");
            return result;
        }

        node = xpath_nodeset_get(nodeset, 0);
        xpath_result_free(arg_result);
    }

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
    if (!result) return NULL;

    result->value.string_value = (node && node->namespace_uri) ?
                                 taurus_strdup(node->namespace_uri) :
                                 taurus_strdup("");
    return result;
}

/* name(node-set?) - Qualified name of first node */
static struct taurus_xpath_result* xpath_func_name(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count > 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "name() takes 0 or 1 argument");
        return NULL;
    }

    struct taurus_element* node;
    if (arg_count == 0) {
        node = context->context_node;
    } else {
        struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
        if (!arg_result) return NULL;

        if (arg_result->type != XPATH_RESULT_NODESET) {
            xpath_result_free(arg_result);
            struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
            if (result) result->value.string_value = taurus_strdup("");
            return result;
        }

        XPathNodeSet* nodeset = arg_result->value.nodeset_value;
        if (!nodeset || xpath_nodeset_count(nodeset) == 0) {
            xpath_result_free(arg_result);
            struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
            if (result) result->value.string_value = taurus_strdup("");
            return result;
        }

        node = xpath_nodeset_get(nodeset, 0);
        xpath_result_free(arg_result);
    }

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
    if (!result) return NULL;

    /* XPath name() returns qualified name, but our implementation stores
     * full qualified name in node->name (e.g., "ns:item").
     * Since we're matching local names everywhere else, return local name here too.
     * TODO: When we properly store prefix separately, return prefix:localname */
    if (!node || !node->name) {
        result->value.string_value = taurus_strdup("");
        return result;
    }

    /* Strip namespace prefix if present */
    const char* colon = strchr(node->name, ':');
    result->value.string_value = taurus_strdup(colon ? colon + 1 : node->name);
    return result;
}

/* id(object) - Select elements by ID */
static struct taurus_xpath_result* xpath_func_id(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "id() requires exactly 1 argument");
        return NULL;
    }

    struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
    if (!arg_result) return NULL;

    char** id_strings = NULL;
    size_t id_count = 0;

    if (arg_result->type == XPATH_RESULT_NODESET) {
        XPathNodeSet* nodeset = arg_result->value.nodeset_value;
        if (nodeset) {
            id_count = xpath_nodeset_count(nodeset);
            if (id_count > 0) {
                id_strings = TAURUS_ALLOC_N(char*, id_count);
                if (id_strings) {
                    for (size_t i = 0; i < id_count; i++) {
                        id_strings[i] = get_node_text(xpath_nodeset_get(nodeset, i));
                    }
                }
            }
        }
    } else {
        char* str = result_to_string(arg_result);
        const char* p = str;
        int in_id = 0;
        while (*p) {
            if (isspace((unsigned char)*p)) {
                in_id = 0;
            } else if (!in_id) {
                id_count++;
                in_id = 1;
            }
            p++;
        }

        if (id_count > 0) {
            id_strings = TAURUS_ALLOC_N(char*, id_count);
            if (id_strings) {
                size_t idx = 0;
                p = str;
                while (*p && isspace((unsigned char)*p)) p++;
                while (*p && idx < id_count) {
                    const char* start = p;
                    while (*p && !isspace((unsigned char)*p)) p++;
                    size_t len = p - start;
                    id_strings[idx] = TAURUS_ALLOC_N(char, len + 1);
                    if (id_strings[idx]) {
                        memcpy(id_strings[idx], start, len);
                        id_strings[idx][len] = '\0';
                        idx++;
                    }
                    while (*p && isspace((unsigned char)*p)) p++;
                }
            }
        }
        TAURUS_FREE(str);
    }
    xpath_result_free(arg_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_NODESET);
    if (!result) {
        for (size_t i = 0; i < id_count; i++) TAURUS_FREE(id_strings[i]);
        TAURUS_FREE(id_strings);
        return NULL;
    }

    result->value.nodeset_value = xpath_nodeset_new();
    if (!result->value.nodeset_value) {
        xpath_result_free(result);
        for (size_t i = 0; i < id_count; i++) TAURUS_FREE(id_strings[i]);
        TAURUS_FREE(id_strings);
        return NULL;
    }

    if (id_count > 0 && context->document && context->document->root) {
        for (size_t i = 0; i < id_count; i++) {
            find_elements_by_id(context->document->root, id_strings[i],
                              result->value.nodeset_value);
        }
    }

    for (size_t i = 0; i < id_count; i++) TAURUS_FREE(id_strings[i]);
    TAURUS_FREE(id_strings);
    return result;
}

/* translate(string, string, string) - Character translation */
static struct taurus_xpath_result* xpath_func_translate(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 3) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "translate() requires 3 arguments");
        return NULL;
    }

    struct taurus_xpath_result* results[3];
    for (int i = 0; i < 3; i++) {
        results[i] = xpath_evaluate(context, args[i]);
        if (!results[i]) {
            for (int j = 0; j < i; j++) xpath_result_free(results[j]);
            return NULL;
        }
    }

    char* str = result_to_string(results[0]);
    char* from = result_to_string(results[1]);
    char* to = result_to_string(results[2]);

    for (int i = 0; i < 3; i++) xpath_result_free(results[i]);

    size_t from_len = strlen(from);
    size_t to_len = strlen(to);
    char* translated = TAURUS_ALLOC_N(char, strlen(str) + 1);
    if (!translated) {
        TAURUS_FREE(str);
        TAURUS_FREE(from);
        TAURUS_FREE(to);
        return NULL;
    }

    char* out = translated;
    const char* in = str;
    while (*in) {
        int found = -1;
        for (size_t i = 0; i < from_len; i++) {
            if (*in == from[i]) {
                found = (int)i;
                break;
            }
        }
        if (found >= 0 && (size_t)found < to_len) {
            *out++ = to[found];
        } else if (found < 0) {
            *out++ = *in;
        }
        in++;
    }
    *out = '\0';

    TAURUS_FREE(str);
    TAURUS_FREE(from);
    TAURUS_FREE(to);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
    if (!result) {
        TAURUS_FREE(translated);
        return NULL;
    }
    result->value.string_value = translated;
    return result;
}

/* substring-before(string, string) - Before delimiter */
static struct taurus_xpath_result* xpath_func_substring_before(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 2) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "substring-before() requires 2 arguments");
        return NULL;
    }

    struct taurus_xpath_result* results[2];
    for (int i = 0; i < 2; i++) {
        results[i] = xpath_evaluate(context, args[i]);
        if (!results[i]) {
            for (int j = 0; j < i; j++) xpath_result_free(results[j]);
            return NULL;
        }
    }

    char* str = result_to_string(results[0]);
    char* delim = result_to_string(results[1]);
    xpath_result_free(results[0]);
    xpath_result_free(results[1]);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
    if (!result) {
        TAURUS_FREE(str);
        TAURUS_FREE(delim);
        return NULL;
    }

    if (delim[0] == '\0') {
        result->value.string_value = taurus_strdup("");
    } else {
        const char* pos = strstr(str, delim);
        if (pos) {
            size_t len = pos - str;
            char* substr = TAURUS_ALLOC_N(char, len + 1);
            if (substr) {
                memcpy(substr, str, len);
                substr[len] = '\0';
                result->value.string_value = substr;
            } else {
                result->value.string_value = taurus_strdup("");
            }
        } else {
            result->value.string_value = taurus_strdup("");
        }
    }

    TAURUS_FREE(str);
    TAURUS_FREE(delim);
    return result;
}

/* substring-after(string, string) - After delimiter */
static struct taurus_xpath_result* xpath_func_substring_after(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 2) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "substring-after() requires 2 arguments");
        return NULL;
    }

    struct taurus_xpath_result* results[2];
    for (int i = 0; i < 2; i++) {
        results[i] = xpath_evaluate(context, args[i]);
        if (!results[i]) {
            for (int j = 0; j < i; j++) xpath_result_free(results[j]);
            return NULL;
        }
    }

    char* str = result_to_string(results[0]);
    char* delim = result_to_string(results[1]);
    xpath_result_free(results[0]);
    xpath_result_free(results[1]);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_STRING);
    if (!result) {
        TAURUS_FREE(str);
        TAURUS_FREE(delim);
        return NULL;
    }

    if (delim[0] == '\0') {
        result->value.string_value = taurus_strdup(str);
    } else {
        const char* pos = strstr(str, delim);
        result->value.string_value = pos ? taurus_strdup(pos + strlen(delim)) : taurus_strdup("");
    }

    TAURUS_FREE(str);
    TAURUS_FREE(delim);
    return result;
}

/* Helper to get xml:lang attribute */
static char* get_lang_attribute(struct taurus_element* node) {
    if (!node) return NULL;

    for (size_t i = 0; i < node->attributes_count; i++) {
        struct taurus_attribute* attr = node->attributes[i];
        if (attr && attr->name && strcmp(attr->name, "xml:lang") == 0) {
            return attr->value ? taurus_strdup(attr->value) : NULL;
        }
    }

    return node->parent ? get_lang_attribute(node->parent) : NULL;
}

/* lang(string) - Check xml:lang matches */
static struct taurus_xpath_result* xpath_func_lang(
    XPathContext* context,
    XPathASTNode** args,
    size_t arg_count
) {
    if (arg_count != 1) {
        snprintf(context->error_msg, sizeof(context->error_msg),
                "lang() requires 1 argument");
        return NULL;
    }

    struct taurus_xpath_result* arg_result = xpath_evaluate(context, args[0]);
    if (!arg_result) return NULL;

    char* target_lang = result_to_string(arg_result);
    xpath_result_free(arg_result);

    struct taurus_xpath_result* result = xpath_result_new(XPATH_RESULT_BOOLEAN);
    if (!result) return NULL;

    char* node_lang = get_lang_attribute(context->context_node);
    if (!node_lang) {
        result->value.boolean_value = 0;
    } else {
        size_t target_len = strlen(target_lang);
        size_t node_len = strlen(node_lang);
        int matches = (node_len >= target_len &&
                      strncasecmp(node_lang, target_lang, target_len) == 0 &&
                      (node_len == target_len || node_lang[target_len] == '-'));
        result->value.boolean_value = matches;
        TAURUS_FREE(node_lang);
    }

    TAURUS_FREE(target_lang);
    return result;
}

/* ============================================================================
 * Standard Function Library Initialization
 * ============================================================================ */

void xpath_function_registry_init_standard(XPathFunctionRegistry* registry) {
    if (!registry) return;

    /* Core functions */
    xpath_function_registry_register(registry, "last", xpath_func_last, 0, 0);
    xpath_function_registry_register(registry, "position", xpath_func_position, 0, 0);

    /* String functions */
    xpath_function_registry_register(registry, "string", xpath_func_string, 0, 1);
    xpath_function_registry_register(registry, "concat", xpath_func_concat, 2, -1);
    xpath_function_registry_register(registry, "starts-with", xpath_func_starts_with, 2, 2);
    xpath_function_registry_register(registry, "contains", xpath_func_contains, 2, 2);
    xpath_function_registry_register(registry, "substring", xpath_func_substring, 2, 3);
    xpath_function_registry_register(registry, "string-length", xpath_func_string_length, 0, 1);
    xpath_function_registry_register(registry, "normalize-space", xpath_func_normalize_space, 0, 1);
    xpath_function_registry_register(registry, "translate", xpath_func_translate, 3, 3);
    xpath_function_registry_register(registry, "substring-before", xpath_func_substring_before, 2, 2);
    xpath_function_registry_register(registry, "substring-after", xpath_func_substring_after, 2, 2);

    /* Boolean functions */
    xpath_function_registry_register(registry, "boolean", xpath_func_boolean, 1, 1);
    xpath_function_registry_register(registry, "not", xpath_func_not, 1, 1);
    xpath_function_registry_register(registry, "true", xpath_func_true, 0, 0);
    xpath_function_registry_register(registry, "false", xpath_func_false, 0, 0);
    xpath_function_registry_register(registry, "lang", xpath_func_lang, 1, 1);

    /* Number functions */
    xpath_function_registry_register(registry, "number", xpath_func_number, 0, 1);
    xpath_function_registry_register(registry, "sum", xpath_func_sum, 1, 1);
    xpath_function_registry_register(registry, "floor", xpath_func_floor, 1, 1);
    xpath_function_registry_register(registry, "ceiling", xpath_func_ceiling, 1, 1);
    xpath_function_registry_register(registry, "round", xpath_func_round, 1, 1);

    /* Node-set functions */
    xpath_function_registry_register(registry, "count", xpath_func_count, 1, 1);
    xpath_function_registry_register(registry, "id", xpath_func_id, 1, 1);
    xpath_function_registry_register(registry, "local-name", xpath_func_local_name, 0, 1);
    xpath_function_registry_register(registry, "namespace-uri", xpath_func_namespace_uri, 0, 1);
    xpath_function_registry_register(registry, "name", xpath_func_name, 0, 1);
}

/* ============================================================================
 * Public XPath Function Support API (for libtaurus)
 * ============================================================================ */

/* Array of all supported function names (NULL-terminated) */
static const char* g_supported_functions[] = {
    /* Core */
    "last",
    "position",
    /* String */
    "string",
    "concat",
    "starts-with",
    "contains",
    "substring-before",
    "substring-after",
    "substring",
    "string-length",
    "normalize-space",
    "translate",
    /* Boolean */
    "boolean",
    "not",
    "true",
    "false",
    "lang",
    /* Number */
    "number",
    "sum",
    "floor",
    "ceiling",
    "round",
    /* Node-set */
    "count",
    "id",
    "local-name",
    "namespace-uri",
    "name",
    NULL  /* Terminator */
};

/**
 * Check if XPath function is supported
 */
TAURUS_API int taurus_xpath_function_supported(const char* function_name) {
    if (!function_name) return 0;

    for (size_t i = 0; g_supported_functions[i] != NULL; i++) {
        if (strcmp(function_name, g_supported_functions[i]) == 0) {
            return 1;
        }
    }
    return 0;
}

/**
 * Get list of supported XPath functions
 */
TAURUS_API const char** taurus_xpath_supported_functions(void) {
    return g_supported_functions;
}
