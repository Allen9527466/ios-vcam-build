ARCHS = arm64
TARGET = iphone:clang:15.6:15.0
SDKVERSION = 15.6
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FakeCam

FakeCam_FILES = Tweak.x
FakeCam_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
