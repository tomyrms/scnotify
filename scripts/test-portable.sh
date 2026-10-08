#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -p "test_*.py" -v
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
"${CC:-clang}" -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -g \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  Core/SNCore.c tests/fuzz_core.c -o "$build/fuzz_core"
"$build/fuzz_core" tests/fixtures/call_start.bin
"${CC:-clang}" -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -g \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  Core/SNReceivePolicy.c tests/fuzz_receive.c -o "$build/fuzz_receive"
"$build/fuzz_receive"
