#import <UIKit/UIKit.h>
#import "LPOverlayCoordinator.h"

%hook SBDashBoardMainPageView

- (void)didMoveToWindow {
    %orig;

    if (self.window != nil) {
        [[LPOverlayCoordinator sharedCoordinator] attachToHostView:self];
    } else {
        [[LPOverlayCoordinator sharedCoordinator] detachFromHostView:self];
    }
}

%end

%ctor {
    @autoreleasepool {
        [LPOverlayCoordinator sharedCoordinator];
    }
}
