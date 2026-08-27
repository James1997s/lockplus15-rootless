from pathlib import Path

p = Path('/home/ubuntu/lockplus15-rootless/LPOverlayCoordinator.m')
s = p.read_text()
old = '''    // A clean install has no selected cached theme. Keep SpringBoard's stock
    // date/clock visible until the user explicitly downloads and selects one.
    return enabled && [[LPThemeCatalog sharedCatalog] activeThemeJSON].length > 0;'''
new = '''    // Keep an already-rendered folder theme enabled while SpringBoard or the
    // catalog briefly rebuilds its active-theme cache during unlock. A clean
    // install still falls back to the stock date because no renderer exists.
    NSString *activeTheme = [[LPThemeCatalog sharedCatalog] activeThemeJSON];
    return enabled && (activeTheme.length > 0 || self.themeRenderer != nil);'''
if old not in s:
    raise SystemExit('isEnabled block not found')
s = s.replace(old, new)
old = '''    UIView *host = self.hostView;
    [self detachFromHostView:host];
    if (host != nil && self.isEnabled) {
        [self attachToHostView:host];
    } else {
        [[LPThemeCatalog sharedCatalog] synchronizeCatalogWithCompletion:^(BOOL activeThemeUpdated) {
            // The catalog cache has been refreshed. It will be rendered the next time the host attaches.
        }];
    }'''
new = '''    UIView *host = self.hostView;
    if (host != nil && (self.isEnabled || self.themeRenderer != nil)) {
        [self attachToHostView:host];
    } else {
        [[LPThemeCatalog sharedCatalog] synchronizeCatalogWithCompletion:^(BOOL activeThemeUpdated) {
            // The catalog cache has been refreshed. It will be rendered when
            // the lock-screen date host is available again.
        }];
    }'''
if old not in s:
    raise SystemExit('refresh block not found')
s = s.replace(old, new)
old = '''    if (!self.isEnabled) {
        return;
    }
    UIView *currentHost = self.stockDateView.superview;'''
new = '''    if (!self.isEnabled && self.themeRenderer == nil) {
        return;
    }
    UIView *currentHost = self.stockDateView.superview;'''
if old not in s:
    raise SystemExit('monitor guard not found')
s = s.replace(old, new, 1)
old = '''    if (hostView == nil || !self.isEnabled) {
        return;
    }'''
new = '''    if (hostView == nil || (!self.isEnabled && self.themeRenderer == nil)) {
        return;
    }'''
if old not in s:
    raise SystemExit('attach guard not found')
s = s.replace(old, new, 1)
# Protect the async catalog reload from replacing a live renderer with an empty cache.
old = '''        if (activeThemeUpdated && self.themeRenderer == renderer) {
            [renderer reloadWithThemeJSONString:[self activeThemeJSON]];
        }'''
new = '''        NSString *updatedTheme = [self activeThemeJSON];
        if (activeThemeUpdated && updatedTheme.length > 0 && self.themeRenderer == renderer) {
            [renderer reloadWithThemeJSONString:updatedTheme];
        }'''
if old not in s:
    raise SystemExit('async reload block not found')
s = s.replace(old, new)
p.write_text(s)
print('patched renderer persistence state')
