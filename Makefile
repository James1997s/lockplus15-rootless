export THEOS_PACKAGE_SCHEME = rootless

ARCHS = arm64
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockPlus15
LockPlus15_FILES = Tweak.xm LPOverlayCoordinator.m LPThemeCatalog.m LPNativeThemeRenderer.m
LockPlus15_CFLAGS = -fobjc-arc
LockPlus15_FRAMEWORKS = UIKit

BUNDLE_NAME = LockPlus15Prefs
LockPlus15Prefs_FILES = LPHRootListController.m LPHThemePickerController.m
LockPlus15Prefs_CFLAGS = -fobjc-arc
LockPlus15Prefs_FRAMEWORKS = UIKit
LockPlus15Prefs_PRIVATE_FRAMEWORKS = Preferences
LockPlus15Prefs_RESOURCE_FILES = Root.plist Info.plist
LockPlus15Prefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "sbreload"
