TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Media

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MusicPort
MusicPort_FILES = Tweak.x MPLog.m MPHierarchyProbe.m MPPortController.m MPLandscapeHost.m
MusicPort_CFLAGS = -fobjc-arc
MusicPort_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
