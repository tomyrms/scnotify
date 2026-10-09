.DEFAULT_GOAL := all

# `make test` does not require Theos, an SDK or a connected iPhone.
ifeq ($(filter test test-macos,$(MAKECMDGOALS)),)
ifneq ($(strip $(THEOS)),)
ARCHS = arm64
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = SnapNotify
SnapNotify_FILES = Tweak.m Sources/SNRuntime.m Sources/SNReceive.m Sources/SNHostNotice.m Sources/SNForeground.m Sources/SNEventBuffer.m Sources/SNPresenceActivity.m Core/SNCore.c Core/SNDeliveryState.c Core/SNReceivePolicy.c Core/SNPresenceWire.c
SnapNotify_FRAMEWORKS = Foundation CoreFoundation UIKit AVFoundation UserNotifications
SnapNotify_CFLAGS = -std=gnu11 -Wall -Wextra -Werror -Wno-deprecated-declarations -O2
SnapNotify_OBJCFLAGS = -fobjc-arc -fblocks
SnapNotify_LDFLAGS = -Wl,-dead_strip
include $(THEOS)/makefiles/tweak.mk
else
.PHONY: all clean
all:
	bash scripts/build-macos.sh
clean:
	rm -rf build out .theos packages
endif
endif

.PHONY: test test-macos
test:
	bash scripts/test-portable.sh
test-macos:
	bash scripts/test-macos.sh
