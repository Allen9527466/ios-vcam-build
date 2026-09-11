ARCHS = arm64 arm64e
TARGET = iphone:clang:15.0:15.0

INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

DYLIB_NAME = VirtualCam

VirtualCam_FILES = main.m
VirtualCam_CFLAGS = -fobjc-arc
# 增加 substrate 框架
VirtualCam_FRAMEWORKS = CoreVideo UIKit AVFoundation Substrate

include $(THEOS_MAKE_PATH)/dylib.mk
