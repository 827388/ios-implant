TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
FINALPACKAGE = 1
STRIP = 0
GO_EASY_ON_ME = 1

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = SpringBoardTweak

SpringBoardTweak_FILES = SpringBoardTweak.m
SpringBoardTweak_CFLAGS = -fobjc-arc -O2 -DALERT_PROBE=0
SpringBoardTweak_FRAMEWORKS = Foundation UIKit
SpringBoardTweak_INSTALL_PATH = /usr/local/lib

include $(THEOS_MAKE_PATH)/library.mk

# 探测版（用来确认 bootstrap 调的是哪个入口符号）
probe::
	$(MAKE) clean
	$(MAKE) SpringBoardTweak_CFLAGS="-fobjc-arc -O2 -DALERT_PROBE=1"

# 编译产物位置：.theos/obj/debug/SpringBoardTweak.dylib
#               或 .theos/obj/arm64e/SpringBoardTweak.dylib
