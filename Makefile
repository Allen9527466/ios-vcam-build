ARCHS = arm64
TARGET = iphone:clang:15.0:14.0
INSTALL_PROGRAM = NO

VirtualCam_FILES = main.m
VirtualCam_CFLAGS = -fobjc-arc
VirtualCam_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia
VirtualCam_LDFLAGS = -ldl

include $(THEOS_MAKE_PATH)/dylib.mk
