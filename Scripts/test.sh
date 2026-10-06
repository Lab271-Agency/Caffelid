#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift test --disable-sandbox
clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I Sources/CaffelidSensors/include Tests/temperature_reader.c -framework IOKit \
    -o "$PROJECT_DIR/.build/temperature-reader-test"
"$PROJECT_DIR/.build/temperature-reader-test"
python3 "$PROJECT_DIR/Tests/helper_integration.py"
