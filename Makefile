all: VirtualCamDylib.dylib

VirtualCamDylib.dylib: VirtualCamDylib.swift
	swiftc -emit-library -o VirtualCamDylib.dylib VirtualCamDylib.swift \
	-target arm64-apple-ios14.0 \
	-sdk $(shell xcrun --sdk iphoneos --show-sdk-path)

clean:
	rm -f VirtualCamDylib.dylib
