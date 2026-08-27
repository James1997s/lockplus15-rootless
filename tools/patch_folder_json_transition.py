from pathlib import Path

p = Path('/home/ubuntu/lockplus15-rootless/LPNativeThemeRenderer.m')
s = p.read_text()

s = s.replace('@property (nonatomic, copy) NSString *folderReadRoot;\n', '@property (nonatomic, copy) NSString *folderReadRoot;\n@property (nonatomic, assign) NSUInteger folderLoadGeneration;\n')

needle = '''- (void)stopRendering {
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    self.folderWebView.navigationDelegate = nil;
    [self.folderWebView stopLoading];
    [self.folderWebView removeFromSuperview];
    self.folderWebView = nil;
    self.folderReadRoot = nil;
}
'''
replacement = '''- (void)stopRendering {
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    self.folderLoadGeneration += 1;
    self.folderWebView.navigationDelegate = nil;
    [self.folderWebView stopLoading];
    [self.folderWebView removeFromSuperview];
    self.folderWebView = nil;
    self.folderReadRoot = nil;
}

- (void)clearNativeRenderedContent {
    [self stopRendering];
    for (UIView *view in [self.subviews copy]) {
        [view removeFromSuperview];
    }
    [self.elements removeAllObjects];
    [self.ecgTimeViews removeAllObjects];
    [self.brushstrokeTimeViews removeAllObjects];
}
'''
if needle not in s:
    raise SystemExit('stopRendering block not found')
s = s.replace(needle, replacement)

old = '''- (void)reloadCurrentFolderDocument {
    NSString *themeID = [self selectedThemeID];
    if (themeID.length == 0 || self.folderWebView == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self loadFolderThemeWithID:themeID];
    });
}'''
new = '''- (void)reloadCurrentFolderDocument {
    NSString *themeID = [self selectedThemeID];
    WKWebView *webView = self.folderWebView;
    NSUInteger generation = self.folderLoadGeneration;
    if (themeID.length == 0 || webView == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        // Ignore a delayed callback from a folder that has already been
        // replaced by a JSON/native theme.
        if (self.folderWebView == webView && self.folderLoadGeneration == generation) {
            [self loadFolderThemeWithID:themeID];
        }
    });
}'''
if old not in s:
    raise SystemExit('reloadCurrentFolderDocument block not found')
s = s.replace(old, new)

old = '''- (void)reloadWithThemeJSONString:(NSString *)themeJSONString {
    NSData *data = [themeJSONString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *theme = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([theme isKindOfClass:NSDictionary.class] && [theme[@"format"] isEqualToString:@"folder"]) {
        [self loadFolderThemeWithID:[self selectedThemeID]];
        return;
    }

    [self stopRendering];
    for (UIView *view in self.subviews) {
        [view removeFromSuperview];
    }
    [self.elements removeAllObjects];
    [self.ecgTimeViews removeAllObjects];
    [self.brushstrokeTimeViews removeAllObjects];'''
new = '''- (void)reloadWithThemeJSONString:(NSString *)themeJSONString {
    NSData *data = [themeJSONString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *theme = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([theme isKindOfClass:NSDictionary.class] && [theme[@"format"] isEqualToString:@"folder"]) {
        [self loadFolderThemeWithID:[self selectedThemeID]];
        return;
    }

    // JSON/native mode must never share the renderer’s folder WebView or any
    // elements left by the previous mode. Clear the complete content set in a
    // single main-thread transaction before adding native views.
    [self clearNativeRenderedContent];'''
if old not in s:
    raise SystemExit('reloadWithThemeJSONString block not found')
s = s.replace(old, new)
p.write_text(s)
print('patched folder-to-JSON transition cleanup')
