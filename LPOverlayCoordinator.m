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
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, strong) UIView *stockDateView;
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

    UIView *host = self.hostView;
    if (host != nil && (self.isEnabled || self.themeRenderer != nil)) {
        [self attachToHostView:host];
    } else {
        [[LPThemeCatalog sharedCatalog] synchronizeCatalogWithCompletion:^(BOOL activeThemeUpdated) {
            // The catalog cache has been refreshed. It will be rendered when
            // the lock-screen date host is available again.
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
    if (!self.isEnabled && self.themeRenderer == nil) {
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
        }
        [self startHostMonitor];
        return;
    }

    self.hostView = hostView;

    UIView *overlay = [[UIView alloc] initWithFrame:hostView.bounds];
    overlay.backgroundColor = UIColor.clearColor;
    overlay.opaque = NO;
    overlay.layer.zPosition = 0.0;
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
