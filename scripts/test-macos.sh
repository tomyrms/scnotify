#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $(uname -s) != Darwin ]]; then
  echo 'This test requires macOS Foundation and the Objective-C runtime.' >&2
  exit 2
fi
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
xcrun clang -std=gnu11 -Wall -Wextra -Werror -c Core/SNCore.c -o "$build/core.o"
xcrun clang -std=gnu11 -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -framework Foundation \
  Sources/SNRuntime.m tests/TestFoundation.m "$build/core.o" -o "$build/test_foundation"
"$build/test_foundation"
