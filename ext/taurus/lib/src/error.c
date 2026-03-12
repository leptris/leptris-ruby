/* error.c - Taurus error handling implementation
 * Copyright (c) 2024, Ribose Inc.
 *
 * Error handling with thread-local storage
 */

#include "taurus/taurus.h"
#include "taurus_internal.h"
#include <string.h>

/* ============================================================================
 * Thread-Local Error State
 * ============================================================================ */

/* Thread-local error state structure */
typedef struct {
    char message[512];
    char context_snippet[256];  /* Context around error position */
    taurus_error_code code;
    int line;
    int column;
    size_t byte_offset;          /* Byte offset in input */
} taurus_error_state;

/* Thread-local storage for error state */
#ifdef _WIN32
    __declspec(thread) static taurus_error_state g_error_state = {{0}, {0}, TAURUS_OK, 0, 0, 0};
#else
    static __thread taurus_error_state g_error_state = {{0}, {0}, TAURUS_OK, 0, 0, 0};
#endif

/* ============================================================================
 * Internal Error Setting (for use by parser/evaluator)
 * ============================================================================ */

void taurus_set_error(taurus_error_code code, const char* message) {
    g_error_state.code = code;
    if (message) {
        strncpy(g_error_state.message, message, sizeof(g_error_state.message) - 1);
        g_error_state.message[sizeof(g_error_state.message) - 1] = '\0';
    } else {
        g_error_state.message[0] = '\0';
    }
}

void taurus_set_parse_error_position(int line, int column) {
    g_error_state.line = line;
    g_error_state.column = column;
}

void taurus_set_error_with_context(
    taurus_error_code code,
    const char* message,
    const char* input,
    size_t byte_offset,
    int line,
    int column
) {
    g_error_state.code = code;
    g_error_state.line = line;
    g_error_state.column = column;
    g_error_state.byte_offset = byte_offset;
    
    /* Copy message */
    if (message) {
        strncpy(g_error_state.message, message, sizeof(g_error_state.message) - 1);
        g_error_state.message[sizeof(g_error_state.message) - 1] = '\0';
    } else {
        g_error_state.message[0] = '\0';
    }
    
    /* Extract context snippet if input provided */
    if (input) {
        taurus_extract_context_snippet(
            input,
            byte_offset,
            line,
            g_error_state.context_snippet,
            sizeof(g_error_state.context_snippet)
        );
    } else {
        g_error_state.context_snippet[0] = '\0';
    }
}

/* Extract context snippet (±2 lines around error position) */
void taurus_extract_context_snippet(
    const char* input,
    size_t offset,
    int error_line,
    char* out_buffer,
    size_t buffer_size
) {
    if (!input || !out_buffer || buffer_size == 0) {
        return;
    }
    
    /* Find current line start */
    const char* current_line_start = input + offset;
    while (current_line_start > input && *(current_line_start - 1) != '\n') {
        current_line_start--;
    }
    
    /* Find current line end */
    const char* current_line_end = input + offset;
    while (*current_line_end && *current_line_end != '\n') {
        current_line_end++;
    }
    
    /* Calculate position within line for marker */
    size_t marker_pos = (size_t)(input + offset - current_line_start);
    
    /* Copy the current line */
    size_t line_len = (size_t)(current_line_end - current_line_start);
    
    /* Check if we have enough space for line + newline + marker + null */
    size_t needed_space = line_len + 1 + marker_pos + 1 + 1;  /* line + \n + spaces + ^ + \0 */
    
    if (needed_space > buffer_size) {
        /* Not enough space for marker, just copy truncated line */
        size_t max_copy = buffer_size > 1 ? buffer_size - 1 : 0;
        if (line_len > max_copy) {
            line_len = max_copy;
        }
        if (line_len > 0) {
            memcpy(out_buffer, current_line_start, line_len);
        }
        out_buffer[line_len] = '\0';
        return;
    }
    
    /* We have enough space - copy line + marker */
    size_t write_pos = 0;
    
    /* Copy line content */
    memcpy(out_buffer + write_pos, current_line_start, line_len);
    write_pos += line_len;
    
    /* Add newline */
    out_buffer[write_pos++] = '\n';
    
    /* Add marker line with spaces and ^ */
    for (size_t i = 0; i < marker_pos; i++) {
        out_buffer[write_pos++] = ' ';
    }
    out_buffer[write_pos++] = '^';
    out_buffer[write_pos] = '\0';
}

/* ============================================================================
 * Public Error API
 * ============================================================================ */

/**
 * Get last error message
 */
TAURUS_API const char* taurus_last_error(void) {
    if (g_error_state.message[0] == '\0') {
        return NULL;
    }
    return g_error_state.message;
}

/**
 * Clear last error
 */
TAURUS_API void taurus_clear_error(void) {
    g_error_state.message[0] = '\0';
    g_error_state.context_snippet[0] = '\0';
    g_error_state.code = TAURUS_OK;
    g_error_state.line = 0;
    g_error_state.column = 0;
    g_error_state.byte_offset = 0;
}

/**
 * Get error code from parse result
 */
TAURUS_API taurus_error_code taurus_last_error_code(void) {
    return g_error_state.code;
}

/**
 * Convert error code to string
 */
TAURUS_API const char* taurus_error_string(taurus_error_code code) {
    switch (code) {
        case TAURUS_OK:
            return "Success";
            
        /* Parse errors */
        case TAURUS_ERROR_NULL_INPUT:
            return "NULL input provided";
        case TAURUS_ERROR_EMPTY_INPUT:
            return "Empty input provided";
        case TAURUS_ERROR_PARSE_FAILED:
            return "Parse failed (malformed XML)";
        case TAURUS_ERROR_INVALID_XML:
            return "Invalid XML structure";
        case TAURUS_ERROR_UNCLOSED_TAG:
            return "Element tag not closed";
        case TAURUS_ERROR_INVALID_ATTR:
            return "Invalid attribute syntax";
        case TAURUS_ERROR_ENCODING:
            return "Encoding error";
        case TAURUS_ERROR_NAMESPACE:
            return "Namespace error";
        case TAURUS_ERROR_MALFORMED:
            return "Malformed XML";
            
        /* XPath errors */
        case TAURUS_ERROR_XPATH_SYNTAX:
            return "XPath syntax error";
        case TAURUS_ERROR_XPATH_FUNCTION:
            return "Unknown or invalid XPath function";
        case TAURUS_ERROR_XPATH_TYPE_MISMATCH:
            return "XPath type mismatch";
        case TAURUS_ERROR_XPATH_NAMESPACE:
            return "Unregistered namespace prefix in XPath";
        case TAURUS_ERROR_XPATH_UNKNOWN_AXIS:
            return "Unknown XPath axis";
            
        /* Evaluation errors */
        case TAURUS_ERROR_EVAL_CONTEXT:
            return "Invalid evaluation context";
        case TAURUS_ERROR_EVAL_ARGUMENT:
            return "Invalid function argument";
        case TAURUS_ERROR_EVAL_OVERFLOW:
            return "Numeric overflow";
            
        /* Generic errors */
        case TAURUS_ERROR_OUT_OF_MEMORY:
            return "Memory allocation failed";
        case TAURUS_ERROR_INTERNAL:
            return "Internal error";
            
        default:
            return "Unknown error";
    }
}

/**
 * Get parse error line number
 */
TAURUS_API int taurus_parse_error_line(void) {
    return g_error_state.line;
}

/**
 * Get parse error column number
 */
TAURUS_API int taurus_parse_error_column(void) {
    return g_error_state.column;
}

/**
 * Get error context snippet
 */
TAURUS_API const char* taurus_error_context(void) {
    if (g_error_state.context_snippet[0] == '\0') {
        return NULL;
    }
    return g_error_state.context_snippet;
}

/**
 * Get error byte offset
 */
TAURUS_API size_t taurus_error_byte_offset(void) {
    return g_error_state.byte_offset;
}