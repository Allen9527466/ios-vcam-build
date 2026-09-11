ARCHS = arm64
TARGET = iphone:clang:15.0:15.0

INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

DYLIB_NAME = VirtualCam

VirtualCam_FILES = main.m
VirtualCam_CFLAGS = -fobjc-arc
VirtualCam_FRAMEWORKS = CoreVideo UIKit AVFoundation

include $(THEOS_MAKE_PATH)/dylib.mk
