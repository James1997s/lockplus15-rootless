export THEOS_PACKAGE_SCHEME = rootless

ARCHS = arm64
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SpecialLock
SpecialLock_FILES = Tweak.xm LPOverlayCoordinator.m LPThemeCatalog.m LPNativeThemeRenderer.m
SpecialLock_CFLAGS = -fobjc-arc
SpecialLock_FRAMEWORKS = UIKit ImageIO

BUNDLE_NAME = SpecialLockPrefs
SpecialLockPrefs_FILES = LPHRootListController.m LPHThemePickerController.m LPHThemeManagerController.m LPHWallpaperPickerController.m LPThemeCatalog.m
SpecialLockPrefs_CFLAGS = -fobjc-arc
SpecialLockPrefs_FRAMEWORKS = UIKit Foundation ImageIO
SpecialLockPrefs_PRIVATE_FRAMEWORKS = Preferences
SpecialLockPrefs_RESOURCE_FILES = Root.plist Info.plist
SpecialLockPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "sbreload"
