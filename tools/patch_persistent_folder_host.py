from pathlib import Path

root = Path('/home/ubuntu/lockplus15-rootless')
coord = root / 'LPOverlayCoordinator.m'
s = coord.read_text()
s = s.replace('@property (nonatomic, weak) UIView *hostView;', '@property (nonatomic, strong) UIView *hostView;')
s = s.replace('@property (nonatomic, weak) UIView *stockDateView;', '@property (nonatomic, strong) UIView *stockDateView;')
old = '''- (void)ensureOverlayAttachedToCurrentHost {
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
}'''
new = '''- (void)ensureOverlayAttachedToCurrentHost {
    if (!self.isEnabled) {
        return;
    }
    UIView *currentHost = self.stockDateView.superview;
    if (currentHost == nil) {
        return;
    }
    if (self.overlayView.superview != currentHost || self.hostView != currentHost) {
        [self attachToHostView:currentHost];
    }
}'''
if old not in s:
    raise SystemExit('monitor block not found')
s = s.replace(old, new)
start = s.index('- (void)attachToHostView:(UIView *)hostView {')
end = s.index('\n- (void)detachFromHostView:', start)
replacement = '''- (void)attachToHostView:(UIView *)hostView {
    if (hostView == nil || !self.isEnabled) {
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
        if (activeThemeUpdated && self.themeRenderer == renderer) {
            [renderer reloadWithThemeJSONString:[self activeThemeJSON]];
        }
    }];
}'''
s = s[:start] + replacement + s[end:]
coord.write_text(s)

tweak = root / 'Tweak.xm'
t = tweak.read_text()
old_else = '''    } else {
        [coordinator unregisterStockDateView:self];
    }
}'''
new_else = '''    } else {
        // Keep the date view reference across transient unlock removal. The
        // coordinator will reuse the same renderer when the hierarchy returns.
    }
}'''
if old_else not in t:
    raise SystemExit('didMoveToWindow else block not found')
tweak.write_text(t.replace(old_else, new_else, 1))
print('patched persistent folder host lifecycle')
''
