#import <UIKit/UIKit.h>
#import "LPOverlayCoordinator.h"

// SBFLockScreenDateView provides the lock-screen lifecycle. LockPlus inserts a
// non-interactive visual sibling into the date view's parent hierarchy, rather
// than the UIWindow, so SpringBoard's passcode and unlock layers remain above it.
@interface SBFLockScreenDateView : UIView
@end

%hook SBFLockScreenDateView

- (void)didMoveToWindow {
    %orig;

    LPOverlayCoordinator *coordinator = [LPOverlayCoordinator sharedCoordinator];
    if (self.window != nil) {
        [coordinator registerStockDateView:self];
        UIView *visualHost = self.superview;
        if (visualHost != nil) {
            [coordinator attachToHostView:visualHost];
        }
    } else {
        [coordinator unregisterStockDateView:self];
    }
}

- (void)setHidden:(BOOL)hidden {
    LPOverlayCoordinator *coordinator = [LPOverlayCoordinator sharedCoordinator];
    if (coordinator.isApplyingStockDateVisibility) {
        %orig(hidden);
        return;
    }

    if (coordinator.isEnabled) {
        if (hidden) {
            // This is SpringBoard beginning its lock-screen dismissal. Tear down
            // unconditionally before the passcode/home-screen animation advances.
            [coordinator detachCurrentOverlay];
        } else {
            UIView *visualHost = self.superview;
            if (visualHost != nil) {
                [coordinator attachToHostView:visualHost];
            }
        }
        // Suppress Apple's original time/date container while LockPlus is active.
        %orig(YES);
    } else {
        %orig(hidden);
    }
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    LPOverlayCoordinator *coordinator = [LPOverlayCoordinator sharedCoordinator];
    if (newWindow == nil) {
        [coordinator detachCurrentOverlay];
        [coordinator unregisterStockDateView:self];
    }
    %orig;
}

%end

%ctor {
    @autoreleasepool {
        [LPOverlayCoordinator sharedCoordinator];
    }
}
