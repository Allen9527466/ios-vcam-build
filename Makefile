ARCHS = arm64
TARGET = iphone:clang:15.0:14.0
INSTALL_PROGRAM = NO

VirtualCam_FILES = main.m
VirtualCam_CFLAGS = -fobjc-arc
VirtualCam_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia CoreVideo
# 弱链接CoreVideo，解决CI链接器报错，手机系统自带CoreVideo
VirtualCam_LDFLAGS = -Wl,-weak_framework,CoreVideo

include $(THEOS_MAKE_PATH)/dylib.mk
