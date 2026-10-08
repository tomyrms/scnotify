ARCHS = arm64
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SnapNotify
SnapNotify_FILES = Tweak.m
SnapNotify_FRAMEWORKS = Foundation UIKit AVFoundation UserNotifications
SnapNotify_CFLAGS = -fobjc-arc -O2
SnapNotify_LDFLAGS = -Wl,-dead_strip

include $(THEOS)/makefiles/tweak.mk
