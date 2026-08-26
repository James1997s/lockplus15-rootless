#import "LPOverlayCoordinator.h"
#import "LPThemeCatalog.h"

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <rootless.h>

static NSString * const kLPPrefsDomain = @"com.example.lockplus15";
static CFStringRef const kLPPreferencesChanged = CFSTR("com.example.lockplus15/preferences.changed");

static void LPPreferencesChangedCallback(CFNotificationCenterRef center,
                                         void *observer,
                                         CFStringRef name,
                                         const void *object,
                                         CFDictionaryRef userInfo);

@interface LPOverlayCoordinator () <WKNavigationDelegate>
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) WKWebView *webView;
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
                                        LPPreferencesChanged,
                                        LPPreferencesChangedCallback,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)dealloc {
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
    return enabled;
}

- (void)refreshForPreferences {
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
    // The port is visual-only by default. It must not consume the system lock/unlock gestures.
    overlay.userInteractionEnabled = NO;
    overlay.translatesAutoresizingMaskIntoConstraints = NO;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = [[WKUserContentController alloc] init];
    WKUserScript *bootstrap = [[WKUserScript alloc] initWithSource:[self bootstrapJavaScript]
                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                  forMainFrameOnly:YES];
    [configuration.userContentController addUserScript:bootstrap];

    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    webView.navigationDelegate = self;
    webView.opaque = NO;
    webView.backgroundColor = UIColor.clearColor;
    webView.userInteractionEnabled = NO;
    webView.scrollView.scrollEnabled = NO;
    webView.scrollView.bounces = NO;
    webView.scrollView.backgroundColor = UIColor.clearColor;
    webView.translatesAutoresizingMaskIntoConstraints = NO;

    [overlay addSubview:webView];
    [hostView addSubview:overlay];
    [NSLayoutConstraint activateConstraints:@[
        [overlay.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
        [overlay.topAnchor constraintEqualToAnchor:hostView.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor],
        [webView.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [webView.topAnchor constraintEqualToAnchor:overlay.topAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],
    ]];

    self.overlayView = overlay;
    self.webView = webView;

    NSURL *indexURL = [NSURL fileURLWithPath:ROOT_PATH_NS(@"/Library/LockPlus15/LockPlus/index.html")];
    NSURL *readAccessURL = [NSURL fileURLWithPath:ROOT_PATH_NS(@"/Library/LockPlus15") isDirectory:YES];
    [webView loadFileURL:indexURL allowingReadAccessToURL:readAccessURL];
    [[LPThemeCatalog sharedCatalog] synchronizeCatalogWithCompletion:^(BOOL activeThemeUpdated) {
        if (activeThemeUpdated && self.webView == webView) {
            [webView reload];
        }
    }];
}

- (void)detachFromHostView:(UIView *)hostView {
    if (hostView == nil || hostView != self.hostView) {
        return;
    }
    [self.webView stopLoading];
    [self.overlayView removeFromSuperview];
    self.webView = nil;
    self.overlayView = nil;
    self.hostView = nil;
}

- (NSString *)bootstrapJavaScript {
    NSString *themeJSON = [[LPThemeCatalog sharedCatalog] activeThemeJSON];
    if (themeJSON.length == 0) {
        themeJSON = @"{\"placedElements\":{\"clock\":{\"type\":\"clock\",\"position\":\"absolute\",\"left\":\"50%\",\"top\":\"74px\",\"transform\":\"translateX(-50%)\",\"color\":\"#FFFFFF\",\"font-family\":\"HelveticaNeue-UltraLight\",\"font-size\":\"64px\",\"font-weight\":\"200\",\"z-index\":\"10\"}}}";
    }
    return [NSString stringWithFormat:@"(function () {window.LockPlus15 = window.LockPlus15 || {};window.LockPlus15.artworkURL = 'file:///var/jb/var/mobile/Library/LockPlus15/Artwork.jpg';localStorage.setItem('placedElements', JSON.stringify(%@));})();", themeJSON];
}

@end
