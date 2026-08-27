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

@interface LPOverlayCoordinator ()
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, weak) UIView *stockDateView;
@property (nonatomic, assign) BOOL applyingStockDateVisibility;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) LPNativeThemeRenderer *themeRenderer;
@property (nonatomic, strong) NSTimer *hostMonitorTimer;
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
    // A clean install has no selected cached theme. Keep SpringBoard's stock
    // date/clock visible until the user explicitly downloads and selects one.
    return enabled && [[LPThemeCatalog sharedCatalog] activeThemeJSON].length > 0;
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

    UIView *host = self.hostView;
    [self detachFromHostView:host];
    if (host != nil && self.isEnabled) {
        [self attachToHostView:host];
    } else {
        [[LPThemeCatalog sharedCatalog] synchronizeCatalogWithCompletion:^(BOOL activeThemeUpdated) {
            // The catalog cache has been refreshed. It will be rendered the next time the host attaches.
        }];
    }
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
    if (!self.isEnabled || self.stockDateView.window == nil) {
        return;
    }
    UIView *currentHost = self.stockDateView.superview;
    if (currentHost == nil) {
        return;
    }
    if (self.overlayView.superview != currentHost || self.hostView != currentHost) {
        [self attachToHostView:currentHost];
    }
}

- (void)startHostMonitor {
    [self.hostMonitorTimer invalidate];
    self.hostMonitorTimer = [NSTimer scheduledTimerWithTimeInterval:0.50 repeats:YES block:^(NSTimer *timer) {
        [self ensureOverlayAttachedToCurrentHost];
    }];
}

- (void)attachToHostView:(UIView *)hostView {
    if (hostView == nil || !self.isEnabled) {
        return;
    }

    if (self.hostView == hostView && self.overlayView.superview == hostView) {
        return;
    }

    [self detachFromHostView:self.hostView];
    self.hostView = hostView;

    UIView *overlay = [[UIView alloc] initWithFrame:CGRectZero];
    overlay.backgroundColor = UIColor.clearColor;
    overlay.opaque = NO;
    // Keep the visual layer in the host view's normal z-order. This prevents it
    // from sitting above SpringBoard's passcode and unlock presentation layers.
    overlay.layer.zPosition = 0.0;
    // The port is visual-only. It must never consume SpringBoard lock, unlock, notification, camera, or flashlight gestures.
    overlay.userInteractionEnabled = NO;
    overlay.translatesAutoresizingMaskIntoConstraints = NO;

    NSString *themeJSON = [self activeThemeJSON];
    LPNativeThemeRenderer *renderer = [[LPNativeThemeRenderer alloc] initWithThemeJSONString:themeJSON];
    renderer.translatesAutoresizingMaskIntoConstraints = NO;

    [overlay addSubview:renderer];
    [hostView addSubview:overlay];
    [NSLayoutConstraint activateConstraints:@[
        [overlay.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
        [overlay.topAnchor constraintEqualToAnchor:hostView.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor],
        [renderer.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [renderer.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [renderer.topAnchor constraintEqualToAnchor:overlay.topAnchor],
        [renderer.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],
    ]];

    self.overlayView = overlay;
    self.themeRenderer = renderer;
    [self startHostMonitor];

    [[LPThemeCatalog sharedCatalog] synchronizeCatalogWithCompletion:^(BOOL activeThemeUpdated) {
        if (activeThemeUpdated && self.themeRenderer == renderer) {
            [renderer reloadWithThemeJSONString:[self activeThemeJSON]];
        }
    }];
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
