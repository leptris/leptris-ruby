/* error.h - Taurus error handling
 * Copyright (c) 2024, Ribose Inc.
 *
 * Error handling and reporting functions
 */

#ifndef TAURUS_ERROR_H
#define TAURUS_ERROR_H

#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Error Handling
 * ============================================================================ */

/**
 * @brief Get last error message
 * 
 * Returns a human-readable description of the last error that occurred.
 * The string is valid until the next error occurs or the library is
 * unloaded.
 * 
 * @return Error message string, or NULL if no error has occurred
 * 
 * @note Thread-safe: Each thread has its own error state
 * @note The returned string should not be freed by the caller
 */
TAURUS_API const char* taurus_last_error(void);

/**
 * @brief Clear last error
 * 
 * Clears the last error message. After calling this function,
 * taurus_last_error() will return NULL until another error occurs.
 */
TAURUS_API void taurus_clear_error(void);

/**
 * @brief Get error code from parse result
 * 
 * If a parse operation returns NULL, this function can be used to
 * determine the specific error code.
 * 
 * @return Error code from taurus_error_code enum
 * 
 * @see taurus_error_code
 */
TAURUS_API taurus_error_code taurus_last_error_code(void);

/**
 * @brief Convert error code to string
 * 
 * Converts an error code to a human-readable string.
 * 
 * @param code Error code to convert
 * @return Static string describing the error (never NULL)
 * 
 * @note The returned string is statically allocated and should not be freed
 */
TAURUS_API const char* taurus_error_string(taurus_error_code code);

/* ============================================================================
 * Parse Error Information
 * ============================================================================ */

/**
 * @brief Get parse error line number
 * 
 * If a parse error occurred, returns the line number where the error
 * was detected (1-based). Only valid if track_positions option was enabled.
 * 
 * @return Line number, or 0 if not available
 */
TAURUS_API int taurus_parse_error_line(void);

/**
 * @brief Get parse error column number
 *
 * If a parse error occurred, returns the column number where the error
 * was detected (1-based). Only valid if track_positions option was enabled.
 *
 * @return Column number, or 0 if not available
 */
TAURUS_API int taurus_parse_error_column(void);

/**
 * @brief Get error context snippet
 *
 * If an error occurred with context information, returns a snippet of the
 * input showing the area around the error (typically ±2 lines).
 *
 * @return Context snippet string, or NULL if not available
 *
 * @note The returned string is owned by the error state and should not be freed
 * @note The snippet is cleared when taurus_clear_error() is called
 */
TAURUS_API const char* taurus_error_context(void);

/**
 * @brief Get error byte offset
 *
 * If an error occurred, returns the byte offset in the input where the
 * error was detected.
 *
 * @return Byte offset, or 0 if not available
 */
TAURUS_API size_t taurus_error_byte_offset(void);

#ifdef __cplusplus
}
#endif

#endif /* TAURUS_ERROR_H */