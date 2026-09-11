ARCHS = arm64
TARGET = iphone:clang:14.0:14.0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FakeCam

FakeCam_FILES = main.m
FakeCam_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo Foundation QuartzCore CoreGraphics MobileCoreServices PhotosUI
FakeCam_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
