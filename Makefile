ARCH = arm64
SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
MIN_VER = 14.0
CC = xcrun clang

CFLAGS = -arch $(ARCH) -isysroot $(SDK) -mios-version-min=$(MIN_VER) -fobjc-arc -O2
FRAMEWORKS = -framework UIKit -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework Foundation -framework QuartzCore -framework CoreGraphics

all: libXUUZ.dylib

libXUUZ.dylib: main.m VirtualVideo.c
	$(CC) $(CFLAGS) -dynamiclib main.m VirtualVideo.c -o libXUUZ.dylib $(FRAMEWORKS)

clean:
	rm -f libXUUZ.dylib *.o
