ARCHS = arm64
TARGET = iphone:clang:15.0:15.0
SDKVERSION = 15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FakeCam

FakeCam_FILES = main.m
FakeCam_CFLAGS = -fobjc-arc
FakeCam_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia CoreVideo MobileCoreServices

include $(THEOS_MAKE_PATH)/tweak.mk
