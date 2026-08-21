# Building Leptris

This guide explains how to build the Leptris C library and run tests.

## Prerequisites

### Required
- **CMake** >= 3.15
- **C99 compiler** (GCC, Clang, or MSVC)
- **Make** or **Ninja** (build system)

### Optional
- **vcpkg** - For package management
- **pkg-config** - For library discovery

## Quick Start

### Build and Test

```bash
# Create build directory
mkdir build
cd build

# Configure
cmake ..

# Build
cmake --build .

# Run tests
ctest --output-on-failure
```

### Installation

```bash
# Install to /usr/local (default)
sudo cmake --install build

# Or install to custom location
cmake --install build --prefix /opt/leptris
```

## Build Options

### CMake Options

Configure with custom options:

```bash
cmake .. \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=ON \
    -DLEPTRIS_BUILD_CLI=OFF \
    -DCMAKE_BUILD_TYPE=Release
```

**Available Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `BUILD_SHARED_LIBS` | `ON` | Build shared libraries (.so/.dylib/.dll) |
| `BUILD_TESTING` | `ON` | Build C unit tests |
| `LEPTRIS_BUILD_CLI` | `OFF` | Build CLI tool (future) |
| `CMAKE_BUILD_TYPE` | - | Build type: `Debug`, `Release`, `RelWithDebInfo` |
| `CMAKE_INSTALL_PREFIX` | `/usr/local` | Installation directory |

### Build Types

**Release Build** (optimized):
```bash
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build .
```

**Debug Build** (with symbols):
```bash
cmake .. -DCMAKE_BUILD_TYPE=Debug
cmake --build .
```

**Static Library**:
```bash
cmake .. -DBUILD_SHARED_LIBS=OFF
cmake --build .
```

## Platform-Specific Instructions

### macOS (Apple Silicon/Intel)

```bash
# Using system compiler (Clang)
mkdir build && cd build
cmake ..
cmake --build .
ctest

# Install
sudo cmake --install .
```

### Linux (Ubuntu/Debian)

```bash
# Install dependencies
sudo apt-get install build-essential cmake

# Build
mkdir build && cd build
cmake ..
cmake --build .
ctest

# Install
sudo cmake --install .
```

### Linux (Fedora/RHEL)

```bash
# Install dependencies
sudo dnf install gcc cmake make

# Build
mkdir build && cd build
cmake ..
cmake --build .
ctest

# Install
sudo cmake --install .
```

### Windows (MSVC)

```powershell
# Using Visual Studio Developer Command Prompt
mkdir build
cd build
cmake ..
cmake --build . --config Release

# Run tests
ctest -C Release

# Install (as Administrator)
cmake --install . --config Release
```

### Windows (MinGW)

```bash
# Using MinGW/MSYS2
mkdir build && cd build
cmake .. -G "MinGW Makefiles"
cmake --build .
ctest

# Install
cmake --install .
```

## Using vcpkg

### Install via vcpkg

```bash
# Clone leptris repository
git clone https://github.com/leptris/leptris.git

# Install using local port
vcpkg install leptris --overlay-ports=./leptris/ports

# Or after submission to vcpkg registry:
vcpkg install leptris
```

### Use in CMake Project

```cmake
# Find leptris package
find_package(leptris CONFIG REQUIRED)

# Link to your target
target_link_libraries(your_app PRIVATE leptris::leptris)
```

### Use with pkg-config

```bash
# Check installation
pkg-config --modversion leptris
pkg-config --cflags leptris
pkg-config --libs leptris

# Compile with pkg-config
gcc main.c $(pkg-config --cflags --libs leptris) -o myapp
```

## Running Tests

### All Tests

```bash
cd build
ctest --output-on-failure
```

### Specific Test

```bash
cd build
./test/test_lexer
./test/test_parser
./test/test_evaluator
./test/test_functions
```

### Test with Verbose Output

```bash
cd build
ctest --verbose
```

### Test Labels

```bash
# Run only unit tests
ctest -L unit
```

## Installed Files

After installation, the following files are available:

```
/usr/local/
├── include/
│   └── leptris/
│       └── leptris.h          # Public API header
├── lib/
│   ├── libleptris.so          # Shared library (Linux)
│   ├── libleptris.dylib       # Shared library (macOS)
│   ├── libleptris.a           # Static library
│   ├── pkgconfig/
│   │   └── leptris.pc         # pkg-config file
│   └── cmake/
│       └── leptris/
│           ├── leptris-config.cmake
│           ├── leptris-config-version.cmake
│           └── leptris-targets.cmake
└── share/
    └── leptris/
        └── copyright         # License file
```

## Using Installed Library

### C Example

```c
#include <leptris/leptris.h>
#include <stdio.h>

int main() {
    const char* xml = "<root><item>Hello</item></root>";
    
    // Parse XML
    struct leptris_document* doc = leptris_parse(xml, strlen(xml));
    if (!doc) {
        fprintf(stderr, "Parse failed\n");
        return 1;
    }
    
    // Get root element
    struct leptris_element* root = leptris_document_root(doc);
    printf("Root: %s\n", leptris_element_name(root));
    
    // Evaluate XPath
    struct leptris_xpath_result* result = 
        leptris_xpath_eval(doc, "//item", 6);
    
    // Cleanup
    leptris_xpath_result_free(result);
    leptris_document_free(doc);
    
    return 0;
}
```

### Compile Example

```bash
# Using pkg-config
gcc example.c $(pkg-config --cflags --libs leptris) -o example

# Using CMake find_package
# See CMakeLists.txt example above
```

## Troubleshooting

### Build Fails with "CMake not found"

Install CMake:
```bash
# macOS
brew install cmake

# Ubuntu/Debian
sudo apt-get install cmake

# Fedora/RHEL
sudo dnf install cmake
```

### Build Fails with "C compiler not found"

Install development tools:
```bash
# macOS
xcode-select --install

# Ubuntu/Debian
sudo apt-get install build-essential

# Fedora/RHEL
sudo dnf groupinstall "Development Tools"
```

### Tests Fail

```bash
# Clean build directory
cd build
rm -rf *

# Reconfigure and rebuild
cmake ..
cmake --build .

# Run tests with verbose output
ctest --verbose --rerun-failed --output-on-failure
```

### Library Not Found After Installation

Update library cache:
```bash
# Linux
sudo ldconfig

# macOS - add to DYLD_LIBRARY_PATH
export DYLD_LIBRARY_PATH=/usr/local/lib:$DYLD_LIBRARY_PATH
```

## Development Build

For development work:

```bash
# Debug build with verbose output
mkdir build-debug && cd build-debug
cmake .. \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build . -- VERBOSE=1

# Run tests
ctest --verbose
```

The `compile_commands.json` file will be generated for IDE integration.

## Clean Build

```bash
# Remove build directory
rm -rf build

# Recreate and build
mkdir build && cd build
cmake ..
cmake --build .
```

## Support

- **Issues**: https://github.com/leptris/leptris/issues
- **Documentation**: https://github.com/leptris/leptris/tree/main/docs
- **License**: BSD-2-Clause