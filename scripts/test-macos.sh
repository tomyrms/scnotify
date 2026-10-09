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
xcrun clang -std=gnu11 -Wall -Wextra -Werror -c Core/SNReceivePolicy.c -o "$build/policy.o"
xcrun clang -std=gnu11 -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -framework Foundation -framework CoreFoundation \
  Sources/SNRuntime.m Sources/SNReceive.m tests/TestFoundation.m "$build/core.o" "$build/policy.o" -o "$build/test_foundation"
"$build/test_foundation"

xcrun clang -std=gnu11 -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -framework Foundation -framework CoreFoundation \
  Sources/SNRuntime.m Sources/SNReceive.m tests/TestReceive.m "$build/core.o" "$build/policy.o" -o "$build/test_receive"
"$build/test_receive"

xcrun clang -std=gnu11 -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -framework Foundation -framework CoreFoundation \
  Sources/SNRuntime.m Sources/SNReceive.m Sources/SNHostNotice.m tests/TestHostNotice.m \
  "$build/core.o" "$build/policy.o" -o "$build/test_host_notice"
"$build/test_host_notice"

xcrun clang -std=gnu11 -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -framework Foundation -framework CoreFoundation \
  Sources/SNRuntime.m Sources/SNReceive.m tests/TestNativeReceive.m \
  "$build/core.o" "$build/policy.o" -o "$build/test_native_receive"
"$build/test_native_receive"

xcrun clang -std=gnu11 -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -framework Foundation -framework CoreFoundation \
  Sources/SNRuntime.m Sources/SNReceive.m Sources/SNForeground.m tests/TestForeground.m \
  "$build/core.o" "$build/policy.o" -o "$build/test_foreground"
"$build/test_foreground"

xcrun clang -std=gnu11 -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -framework Foundation Sources/SNEventBuffer.m tests/TestEventBuffer.m -o "$build/test_event_buffer"
"$build/test_event_buffer"

xcrun clang -std=gnu11 -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -framework Foundation Sources/SNPresenceActivity.m tests/TestPresenceActivity.m -o "$build/test_presence_activity"
"$build/test_presence_activity"
