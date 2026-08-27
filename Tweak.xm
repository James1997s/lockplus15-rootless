#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "LPOverlayCoordinator.h"

// SBFLockScreenDateView provides the lock-screen lifecycle. LockPlus inserts a
// non-interactive visual sibling into the date view's parent hierarchy, rather
// than the UIWindow, so SpringBoard's passcode and unlock layers remain above it.
@interface SBFLockScreenDateView : UIView
@end
@interface SBDashBoardViewController : UIViewController
@end
@interface SBPasscodeLockViewBase : UIView
@end

static char kLPHiddenEmptyNotificationStateKey;

static BOOL LPIsEmptyNotificationStateText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) {
        return NO;
    }
    // This targets only SpringBoard's empty-state copy, not real notification
    // titles, bodies, or notification list views.
    return [text localizedCaseInsensitiveCompare:@"No Older Notifications"] == NSOrderedSame;
}

%hook UILabel

- (void)setText:(NSString *)text {
    if (LPIsEmptyNotificationStateText(text)) {
        objc_setAssociatedObject(self, &kLPHiddenEmptyNotificationStateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.hidden = YES;
        %orig(@"");
        return;
    }
    if ([objc_getAssociatedObject(self, &kLPHiddenEmptyNotificationStateKey) boolValue]) {
        self.hidden = NO;
        objc_setAssociatedObject(self, &kLPHiddenEmptyNotificationStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig(text);
}

- (void)setAttributedText:(NSAttributedString *)text {
    if (LPIsEmptyNotificationStateText(text.string)) {
        objc_setAssociatedObject(self, &kLPHiddenEmptyNotificationStateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.hidden = YES;
        %orig(nil);
        return;
    }
    if ([objc_getAssociatedObject(self, &kLPHiddenEmptyNotificationStateKey) boolValue]) {
        self.hidden = NO;
        objc_setAssociatedObject(self, &kLPHiddenEmptyNotificationStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig(text);
}

%end

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
        // Keep the date view reference across transient unlock removal. The
        // coordinator will reuse the same renderer when the hierarchy returns.
    }
}

- (void)setHidden:(BOOL)hidden {
    LPOverlayCoordinator *coordinator = [LPOverlayCoordinator sharedCoordinator];
    if (coordinator.isApplyingStockDateVisibility) {
        %orig(hidden);
        return;
    }
    if (coordinator.isEnabled) {
        if (!hidden) {
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
    // SpringBoard transiently removes/reparents the date view during unlock
    // and lock-screen hierarchy rebuilds. Do not tear down the HTML renderer
    // here; didMoveToWindow will register the new host when it returns.
    %orig;
}

%end


%hook SBPasscodeLockViewBase
- (void)didMoveToWindow {
    %orig;
    if (self.window != nil) {
        [[LPOverlayCoordinator sharedCoordinator] setLockScreenVisible:NO];
    }
}
%end
%hook SBDashBoardViewController
- (void)viewWillDisappear:(BOOL)animated {
    [[LPOverlayCoordinator sharedCoordinator] setLockScreenVisible:NO];
    %orig(animated);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    [[LPOverlayCoordinator sharedCoordinator] setLockScreenVisible:YES];
}
%end
%ctor {
    @autoreleasepool {
        [LPOverlayCoordinator sharedCoordinator];
    }
}
