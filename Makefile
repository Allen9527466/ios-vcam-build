ARCHS = arm64 arm64e
TARGET = iphone:clang:15.0:14.0
INSTALL_PROGRAM = NO

VirtualCam_FILES = main.m
VirtualCam_CFLAGS = -fobjc-arc
# 新增 CoreVideo
VirtualCam_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia CoreVideo

include $(THEOS_MAKE_PATH)/dylib.mk
