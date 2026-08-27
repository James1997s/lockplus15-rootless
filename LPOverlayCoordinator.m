#import "LPOverlayCoordinator.h"
#import "LPThemeCatalog.h"
#import "LPNativeThemeRenderer.h"

#import <UIKit/UIKit.h>
#import <rootless.h>

static NSString * const kLPPrefsDomain = @"com.example.speciallock";
static CFStringRef const kLPPreferencesChanged = CFSTR("com.example.speciallock/preferences.changed");

static void LPPreferencesChangedCallback(CFNotificationCenterRef center,
                                         void *observer,
                                         CFStringRef name,
                                         const void *object,
                                         CFDictionaryRef userInfo);

@interface LPEventPassthroughView : UIView
@end

@implementation LPEventPassthroughView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return NO;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
@end

static UIView *LPFullLockScreenHostForView(UIView *view) {
    if (view == nil) {
        return nil;
    }

    // The date view's immediate superview can be only the upper lock-screen
    // content panel. Walk upward, but stop below UIWindow so the renderer does
    // not cover passcode/alert presentation layers. Choose the largest host
    // in the chain; this gives folder HTML a full lock-screen-sized canvas.
    UIView *best = view;
    CGFloat bestArea = MAX(0.0, view.bounds.size.width * view.bounds.size.height);
    UIView *cursor = view;
    while (cursor.superview != nil && ![cursor.superview isKindOfClass:UIWindow.class]) {
        cursor = cursor.superview;
        CGFloat area = MAX(0.0, cursor.bounds.size.width * cursor.bounds.size.height);
        if (area >= bestArea) {
            best = cursor;
            bestArea = area;
        }
    }
    return best;
}

@interface LPOverlayCoordinator ()
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, strong) UIView *stockDateView;
@property (nonatomic, assign) BOOL applyingStockDateVisibility;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) LPNativeThemeRenderer *themeRenderer;
@property (nonatomic, strong) NSTimer *hostMonitorTimer;
@property (nonatomic, assign) BOOL lockScreenVisible;
@end

@implementation LPOverlayCoordinator

+ (instancetype)sharedCoordinator {
    static LPOverlayCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [[self alloc] init];
    });
    return coordinator;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lockScreenVisible = YES;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        LPPreferencesChangedCallback,
                                        kLPPreferencesChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)dealloc {
    [self.hostMonitorTimer invalidate];
    self.hostMonitorTimer = nil;
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       kLPPreferencesChanged,
                                       NULL);
}

static void LPPreferencesChangedCallback(CFNotificationCenterRef center,
                                         void *observer,
                                         CFStringRef name,
                                         const void *object,
                                         CFDictionaryRef userInfo) {
    LPOverlayCoordinator *coordinator = (__bridge LPOverlayCoordinator *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [coordinator refreshForPreferences];
    });
}

- (BOOL)isEnabled {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("enabled"),
                                                        (__bridge CFStringRef)kLPPrefsDomain);
    BOOL enabled = (value != NULL && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value));
    if (value != NULL) {
        CFRelease(value);
    }
    // Keep an already-rendered folder theme enabled while SpringBoard or the
    // catalog briefly rebuilds its active-theme cache during unlock. A clean
    // install still falls back to the stock date because no renderer exists.
    NSString *activeTheme = [[LPThemeCatalog sharedCatalog] activeThemeJSON];
    return enabled && (activeTheme.length > 0 || self.themeRenderer != nil);
}

- (BOOL)isApplyingStockDateVisibility {
    return _applyingStockDateVisibility;
}

- (void)applyStockDateVisibility {
    UIView *stockDateView = self.stockDateView;
    if (stockDateView == nil) {
        return;
    }
    _applyingStockDateVisibility = YES;
    stockDateView.hidden = self.isEnabled;
    _applyingStockDateVisibility = NO;
}

- (void)refreshForPreferences {
    [self applyStockDateVisibility];

    // A preference notification is the cross-process commit signal from the
    // manager. Reload the retained renderer directly; attachToHostView: alone
    // intentionally preserves the existing hierarchy and therefore cannot
    // change the document by itself.
    if (!self.isEnabled) {
        [self detachCurrentOverlay];
        return;
    }
    if (self.themeRenderer != nil) {
        [self applyActiveThemeImmediately];
        return;
    }

    UIView *host = self.hostView ?: self.stockDateView.superview;
    if (host != nil && self.isEnabled) {
        [self attachToHostView:host];
    } else {
        [[LPThemeCatalog sharedCatalog] synchronizeCatalogWithCompletion:^(BOOL activeThemeUpdated) {
            // The catalog cache has been refreshed. It will be rendered when
            // the lock-screen date host is available again.
        }];
    }
}

- (void)applyActiveThemeImmediately {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.isEnabled) {
            return;
        }

        NSString *themeJSON = [self activeThemeJSON];
        if (themeJSON.length == 0) {
            return;
        }

        // Keep the existing overlay/WebView alive when possible. The renderer
        // reloads the newly selected folder entry without waiting for a
        // lock/unlock callback or a SpringBoard restart.
        if (self.themeRenderer != nil) {
            [self.themeRenderer reloadWithThemeJSONString:themeJSON];
            [self ensureOverlayAttachedToCurrentHost];
            [self startHostMonitor];
            return;
        }

        UIView *host = self.stockDateView.superview;
        if (host != nil) {
            [self attachToHostView:host];
        }
    });
}

- (void)registerStockDateView:(UIView *)dateView {
    self.stockDateView = dateView;
    [self applyStockDateVisibility];
}

- (void)unregisterStockDateView:(UIView *)dateView {
    if (dateView == self.stockDateView) {
        self.stockDateView = nil;
    }
}

- (void)ensureOverlayAttachedToCurrentHost {
    if (!self.lockScreenVisible || (!self.isEnabled && self.themeRenderer == nil)) {
        return;
    }
    UIView *currentHost = LPFullLockScreenHostForView(self.stockDateView.superview);
    if (currentHost == nil) {
        return;
    }
    if (self.overlayView.superview != currentHost || self.hostView != currentHost) {
        [self attachToHostView:currentHost];
    } else if (self.overlayView != nil) {
        // SpringBoard can insert a new sibling above us without changing the
        // parent. Restore visual ordering on every monitor tick.
        [currentHost bringSubviewToFront:self.overlayView];
    }
}

- (void)startHostMonitor {
    [self.hostMonitorTimer invalidate];
    self.hostMonitorTimer = [NSTimer scheduledTimerWithTimeInterval:0.50 repeats:YES block:^(NSTimer *timer) {
        if (!self.lockScreenVisible) {
            return;
        }
        [self ensureOverlayAttachedToCurrentHost];
    }];
}

- (void)attachToHostView:(UIView *)hostView {
    if (!self.lockScreenVisible) {
        return;
    }
    hostView = LPFullLockScreenHostForView(hostView);
    if (hostView == nil || (!self.isEnabled && self.themeRenderer == nil)) {
        return;
    }

    // XenHTML-style persistence: retain one renderer and move its visual host
    // when SpringBoard rebuilds the lock-screen hierarchy. Do not stop the
    // WebView just because its temporary parent changed during unlock.
    if (self.overlayView != nil && self.themeRenderer != nil) {
        if (self.overlayView.superview != hostView) {
            [self.overlayView removeFromSuperview];
            self.hostView = hostView;
            self.overlayView.frame = hostView.bounds;
            [hostView addSubview:self.overlayView];
        } else {
            self.overlayView.frame = hostView.bounds;
            [hostView bringSubviewToFront:self.overlayView];
        }
        [self startHostMonitor];
        return;
    }

    self.hostView = hostView;

    UIView *overlay = [[LPEventPassthroughView alloc] initWithFrame:hostView.bounds];
    overlay.backgroundColor = UIColor.clearColor;
    overlay.opaque = NO;
    // Stay above SpringBoard views added later to the date host.
    overlay.layer.zPosition = 1.0;
    overlay.userInteractionEnabled = NO;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    NSString *themeJSON = [self activeThemeJSON];
    LPNativeThemeRenderer *renderer = [[LPNativeThemeRenderer alloc] initWithThemeJSONString:themeJSON];
    renderer.frame = overlay.bounds;
    renderer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [overlay addSubview:renderer];
    [hostView addSubview:overlay];

    self.overlayView = overlay;
    self.themeRenderer = renderer;
    [self startHostMonitor];

    [[LPThemeCatalog sharedCatalog] synchronizeCatalogWithCompletion:^(BOOL activeThemeUpdated) {
        NSString *updatedTheme = [self activeThemeJSON];
        if (activeThemeUpdated && updatedTheme.length > 0 && self.themeRenderer == renderer) {
            [renderer reloadWithThemeJSONString:updatedTheme];
        }
    }];
}
- (void)setLockScreenVisible:(BOOL)visible {
    void (^update)(void) = ^{
        self.lockScreenVisible = visible;
        if (!visible) {
            // Suspend the retained renderer first, then hide the overlay before
            // SpringBoard presents passcode or unlock layers.
            [self.themeRenderer setTransitionSuspended:YES];
            self.overlayView.hidden = YES;
            self.overlayView.alpha = 0.0;
            [self.hostMonitorTimer invalidate];
            self.hostMonitorTimer = nil;
        } else {
            self.overlayView.alpha = 1.0;
            self.overlayView.hidden = NO;
            [self.themeRenderer setTransitionSuspended:NO];
            [self applyStockDateVisibility];
            [self ensureOverlayAttachedToCurrentHost];
            [self startHostMonitor];
        }
    };
    if ([NSThread isMainThread]) {
        update();
    } else {
        dispatch_async(dispatch_get_main_queue(), update);
    }
}

- (void)detachFromHostView:(UIView *)hostView {
    if (hostView == nil || hostView != self.hostView) {
        return;
    }
    [self detachCurrentOverlay];
}

- (void)detachCurrentOverlay {
    [self.hostMonitorTimer invalidate];
    self.hostMonitorTimer = nil;
    [self.themeRenderer stopRendering];
    [self.overlayView removeFromSuperview];
    self.themeRenderer = nil;
    self.overlayView = nil;
    self.hostView = nil;
}

- (NSString *)activeThemeJSON {
    return [[LPThemeCatalog sharedCatalog] activeThemeJSON];
}

@end
