ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = Music Media

include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MusicLandscape
MusicLandscape_FILES = Tweak.xm
MusicLandscape_CFLAGS = -fobjc-arc
MusicLandscape_FRAMEWORKS = UIKit MediaPlayer
include $(THEOS_MAKE_PATH)/tweak.mk
