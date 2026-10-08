#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $(uname -s) != Darwin ]]; then
  echo 'Use the included GitHub Actions workflow or a Mac with full Xcode.' >&2
  exit 2
fi
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
cc=$(xcrun --find clang)
mkdir -p build out
flags=(-arch arm64 -isysroot "$sdk" -miphoneos-version-min=15.0 -std=gnu11
       -Wall -Wextra -Werror -Wno-deprecated-declarations -O2 -fvisibility=hidden)
"$cc" "${flags[@]}" -c Core/SNCore.c -o build/SNCore.o
"$cc" "${flags[@]}" -fobjc-arc -fblocks -c Sources/SNRuntime.m -o build/SNRuntime.o
"$cc" "${flags[@]}" -c Core/SNReceivePolicy.c -o build/SNReceivePolicy.o
"$cc" "${flags[@]}" -fobjc-arc -fblocks -c Sources/SNReceive.m -o build/SNReceive.o
"$cc" "${flags[@]}" -fobjc-arc -fblocks -c Sources/SNHostNotice.m -o build/SNHostNotice.o
"$cc" "${flags[@]}" -fobjc-arc -fblocks -c Sources/SNContent.m -o build/SNContent.o
"$cc" "${flags[@]}" -fobjc-arc -fblocks -c Sources/SNOutbox.m -o build/SNOutbox.o
"$cc" "${flags[@]}" -fobjc-arc -fblocks -c Tweak.m -o build/Tweak.o
"$cc" -arch arm64 -isysroot "$sdk" -miphoneos-version-min=15.0 -dynamiclib \
  build/SNCore.o build/SNReceivePolicy.o build/SNRuntime.o build/SNReceive.o build/SNHostNotice.o build/SNContent.o build/SNOutbox.o build/Tweak.o \
  -framework Foundation -framework CoreFoundation -framework UIKit -framework AVFoundation -framework UserNotifications \
  -Wl,-dead_strip -install_name '@rpath/SnapNotify.dylib' -o out/SnapNotify.dylib
# Ad-hoc library signature only. The complete IPA must be re-signed by the user.
codesign --force --sign - out/SnapNotify.dylib
file out/SnapNotify.dylib
xcrun otool -L out/SnapNotify.dylib
shasum -a 256 out/SnapNotify.dylib > out/SHA256SUMS.txt
