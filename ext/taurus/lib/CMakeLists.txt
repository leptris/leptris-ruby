# Taurus Library - Pure C XML parser and XPath evaluator

# Library source files
set(TAURUS_SOURCES
    src/xpath/lexer.c
    src/xpath/parser.c
    src/xpath/evaluator.c
    src/xpath/functions.c
    src/taurus.c
    src/parse_simple.c
    src/element.c
    src/attribute.c
    src/namespace.c
    src/error.c
)

# Library headers (internal)
set(TAURUS_HEADERS
    src/taurus_internal.h
    src/xpath/xpath_internal.h
    src/xpath/lexer.h
    src/xpath/parser.h
    src/xpath/evaluator.h
    src/xpath/functions.h
)

# Create library target
add_library(taurus ${TAURUS_SOURCES} ${TAURUS_HEADERS})

# Set library properties
set_target_properties(taurus PROPERTIES
    VERSION ${PROJECT_VERSION}
    SOVERSION ${PROJECT_VERSION_MAJOR}
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF
)

# Include directories
target_include_directories(taurus
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_SOURCE_DIR}/src/xpath
)

# Link libraries
target_link_libraries(taurus PRIVATE m)

# Compiler flags
target_compile_options(taurus PRIVATE
    -Wall
    -Wextra
    -Wno-unused-parameter
    $<$<CONFIG:Release>:-O3>
    $<$<CONFIG:Debug>:-g -O0>
)

# Export symbols (for shared libraries)
if(BUILD_SHARED_LIBS)
    target_compile_definitions(taurus PRIVATE TAURUS_BUILDING_DLL)
    target_compile_definitions(taurus PUBLIC TAURUS_DLL)
endif()

# Install library
install(TARGETS taurus
    EXPORT taurus-targets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)

# Install public headers (will create include/taurus/ structure)
install(DIRECTORY include/
    DESTINATION include
    FILES_MATCHING PATTERN "*.h"
)

# Add alias for consistent namespacing
add_library(taurus::taurus ALIAS taurus)