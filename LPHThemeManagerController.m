#import "LPHThemeManagerController.h"

#import <notify.h>
#import <rootless.h>
#import <QuartzCore/QuartzCore.h>

#import "LPThemeCatalog.h"

static NSString * const kLPPreferencesDomain = @"com.example.speciallock";
static NSString * const kLPPreferencesChanged = @"com.example.speciallock/preferences.changed";
static NSString * const kLPThemeDirectory = @"/Library/SpecialLock/Themes";
static NSString * const kLPCachedThemeDirectory = @"/var/mobile/Library/SpecialLock/Themes";
static NSString * const kLPHiddenThemeIDsKey = @"hiddenThemeIDs";


@interface LPThemeVisualCardCell : UITableViewCell
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@end

@implementation LPThemeVisualCardCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        self.contentView.layer.cornerRadius = 16.0;
        self.contentView.layer.masksToBounds = YES;
        self.selectionStyle = UITableViewCellSelectionStyleGray;

        _previewImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _previewImageView.contentMode = UIViewContentModeScaleAspectFill;
        _previewImageView.clipsToBounds = YES;
        _previewImageView.layer.cornerRadius = 12.0;
        [self.contentView addSubview:_previewImageView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.numberOfLines = 2;
        [self.contentView addSubview:_titleLabel];

        _descriptionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _descriptionLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
        _descriptionLabel.textColor = UIColor.secondaryLabelColor;
        _descriptionLabel.numberOfLines = 2;
        [self.contentView addSubview:_descriptionLabel];

        _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _statusLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        _statusLabel.textColor = UIColor.secondaryLabelColor;
        _statusLabel.numberOfLines = 2;
        [self.contentView addSubview:_statusLabel];

        _badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _badgeLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badgeLabel.layer.cornerRadius = 8.0;
        _badgeLabel.layer.masksToBounds = YES;
        [self.contentView addSubview:_badgeLabel];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.contentView.bounds.size.height;
    self.previewImageView.frame = CGRectMake(10.0, 10.0, 78.0, MAX(1.0, h - 20.0));
    CGFloat left = CGRectGetMaxX(self.previewImageView.frame) + 13.0;
    CGFloat right = self.contentView.bounds.size.width - 14.0;
    self.badgeLabel.frame = CGRectMake(MAX(left, right - 76.0), 12.0, MIN(76.0, right - left), 22.0);
    self.titleLabel.frame = CGRectMake(left, 10.0, MAX(1.0, CGRectGetMinX(self.badgeLabel.frame) - left - 8.0), 34.0);
    self.descriptionLabel.frame = CGRectMake(left, 44.0, MAX(1.0, right - left), 30.0);
    self.statusLabel.frame = CGRectMake(left, 76.0, MAX(1.0, right - left), MAX(1.0, h - 82.0));
}
- (void)prepareForReuse {
    [super prepareForReuse];
    self.previewImageView.image = nil;
    self.previewImageView.backgroundColor = UIColor.tertiarySystemFillColor;
    self.descriptionLabel.text = nil;
    self.titleLabel.text = nil;
    self.statusLabel.text = nil;
    self.badgeLabel.text = nil;
}
@end

@interface LPHThemeManagerController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *themeRecords;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIBarButtonItem *refreshButton;
@property (nonatomic, assign, getter=isSynchronizing) BOOL synchronizing;
@property (nonatomic, assign) BOOL hasCachedCatalog;
@end

@implementation LPHThemeManagerController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Theme Manager";
    self.tableView.rowHeight = 108.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.refreshControl = [[UIRefreshControl alloc] init];
    [self.tableView.refreshControl addTarget:self action:@selector(refreshThemes) forControlEvents:UIControlEventValueChanged];

    self.refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshThemes)];
    // Do not set leftBarButtonItem here: Settings supplies the Back button there.
    self.navigationItem.rightBarButtonItem = self.refreshButton;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.bounds.size.width, 96.0)];
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(24.0, 16.0, MAX(1.0, self.view.bounds.size.width - 48.0), 42.0)];
    status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    status.textColor = UIColor.secondaryLabelColor;
    status.numberOfLines = 2;
    status.textAlignment = NSTextAlignmentCenter;
    [header addSubview:status];

    UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progress.frame = CGRectMake(32.0, 72.0, MAX(1.0, self.view.bounds.size.width - 64.0), 2.0);
    progress.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    progress.hidden = YES;
    [header addSubview:progress];

    self.statusLabel = status;
    self.progressView = progress;
    self.tableView.tableHeaderView = header;
    [self reloadThemeRecords];
    [self showIdleStatus];
    [self refreshCatalogSilently];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.isSynchronizing) {
        [self reloadThemeRecords];
    }
}

- (void)showIdleStatus {
    self.statusLabel.text = @"Loading the current GitHub theme list. Theme files download only when you select one.";
    self.progressView.hidden = YES;
}

- (void)refreshCatalogSilently {
    if (self.isSynchronizing) {
        return;
    }
    self.synchronizing = YES;
    self.refreshButton.enabled = NO;
    self.statusLabel.text = @"Refreshing the GitHub theme list…";
    __weak typeof(self) weakSelf = self;
    [[LPThemeCatalog sharedCatalog] refreshCatalogWithCompletion:^(BOOL success) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        self.synchronizing = NO;
        self.refreshButton.enabled = YES;
            if (!success) {
            self.statusLabel.text = @"Could not refresh GitHub. Showing the last available catalog.";
            return;
        }
        [self reloadThemeRecords];
        self.statusLabel.text = [NSString stringWithFormat:@"%lu GitHub themes available. Tap one to download it.", (unsigned long)self.themeRecords.count];
    }];
}

- (void)reloadThemeRecords {
    NSString *cachedCatalogPath = ROOT_PATH_NS([kLPCachedThemeDirectory stringByAppendingPathComponent:@"catalog.json"]);
    NSString *bundledCatalogPath = ROOT_PATH_NS([kLPThemeDirectory stringByAppendingPathComponent:@"catalog.json"]);
    NSData *catalogData = [NSData dataWithContentsOfFile:cachedCatalogPath];
    NSDictionary *catalog = catalogData ? [NSJSONSerialization JSONObjectWithData:catalogData options:0 error:nil] : nil;
    self.hasCachedCatalog = [catalog[@"themes"] isKindOfClass:NSArray.class];
    NSArray *records = self.hasCachedCatalog ? catalog[@"themes"] : nil;
    if (!self.hasCachedCatalog) {
        catalogData = [NSData dataWithContentsOfFile:bundledCatalogPath];
        catalog = catalogData ? [NSJSONSerialization JSONObjectWithData:catalogData options:0 error:nil] : nil;
        records = [catalog[@"themes"] isKindOfClass:NSArray.class] ? catalog[@"themes"] : @[];
    }

    NSMutableArray<NSDictionary *> *available = [NSMutableArray array];
    for (id candidate in records) {
        NSDictionary *record = [candidate isKindOfClass:NSDictionary.class] ? candidate : nil;
        NSString *themeID = [record[@"id"] isKindOfClass:NSString.class] ? record[@"id"] : nil;
        NSString *name = [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : nil;
        NSString *relativePath = [record[@"url"] isKindOfClass:NSString.class] ? record[@"url"] : nil;
        if (themeID.length == 0 || name.length == 0 || relativePath.length == 0) {
            continue;
        }
        NSString *bundledPath = ROOT_PATH_NS([kLPThemeDirectory stringByAppendingPathComponent:relativePath]);
        NSString *cachedPath = ROOT_PATH_NS([kLPCachedThemeDirectory stringByAppendingPathComponent:[themeID stringByAppendingPathExtension:@"json"]]);
        BOOL isBundled = [[NSFileManager defaultManager] fileExistsAtPath:bundledPath];
        BOOL isCached = [[NSFileManager defaultManager] fileExistsAtPath:cachedPath];
        // With a GitHub catalog, only a cached JSON counts as downloaded. Bundled
        // files are used solely as the offline fallback before any catalog exists.
        BOOL locallyAvailable = self.hasCachedCatalog ? isCached : (isCached || isBundled);
        [available addObject:@{ @"id": themeID, @"name": name, @"remoteOnly": @(!isBundled), @"cached": @(locallyAvailable) }];
    }

    self.themeRecords = [available sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
    [self.tableView reloadData];
}

- (void)refreshThemes {
    if (self.isSynchronizing) {
        return;
    }
    self.synchronizing = YES;
    self.refreshButton.enabled = NO;
    self.progressView.hidden = NO;
    self.progressView.progress = 0.0;
        self.statusLabel.text = @"Refreshing the GitHub theme list…";

    __weak typeof(self) weakSelf = self;
    [[LPThemeCatalog sharedCatalog] synchronizeCatalogWithProgress:^(NSUInteger completed, NSUInteger total) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        float fraction = total > 0 ? (float)completed / (float)total : 0.0f;
        [self.progressView setProgress:fraction animated:YES];
        self.statusLabel.text = completed == 0 ? @"Refreshing the GitHub theme list…" : @"GitHub theme list refreshed.";
    } completion:^(BOOL success, BOOL activeThemeUpdated) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        self.synchronizing = NO;
        self.refreshButton.enabled = YES;
            [self.tableView.refreshControl endRefreshing];
        if (!success) {
            self.progressView.hidden = YES;
            self.statusLabel.text = @"Catalog refresh did not complete. Existing theme choices were retained. Check GitHub/network access and try again.";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Catalog Refresh Failed"
                                                                           message:@"The GitHub theme list could not be refreshed. Existing choices remain available."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }

        [self reloadThemeRecords];
        self.progressView.hidden = YES;
        self.statusLabel.text = [NSString stringWithFormat:@"Catalog refreshed. Choose one of %lu GitHub themes to download.", (unsigned long)self.themeRecords.count];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Catalog Ready"
                                                                       message:@"No theme files were downloaded. Tap a theme to download and apply only that theme."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.themeRecords.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Available Themes";
}

- (UIImage *)previewImageForThemeID:(NSString *)themeID {
    if (themeID.length == 0) return nil;
    NSString *path = ROOT_PATH_NS([[@"/var/mobile/Library/SpecialLock/Themes/Assets" stringByAppendingPathComponent:themeID] stringByAppendingPathComponent:@"wallpaper.jpg"]);
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (image == nil) {
        path = ROOT_PATH_NS([[@"/Library/SpecialLock/Themes/Assets" stringByAppendingPathComponent:themeID] stringByAppendingPathComponent:@"wallpaper.jpg"]);
        image = [UIImage imageWithContentsOfFile:path];
    }
    return image;
}

- (UIColor *)previewFallbackColorForThemeID:(NSString *)themeID {
    NSUInteger hash = themeID.hash;
    CGFloat hue = (CGFloat)(hash % 360) / 360.0;
    return [UIColor colorWithHue:hue saturation:0.48 brightness:0.42 alpha:1.0];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const reuseIdentifier = @"ThemeVisualCard";
    LPThemeVisualCardCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil) {
        cell = [[LPThemeVisualCardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    }
    NSDictionary *record = self.themeRecords[indexPath.row];
    NSString *themeID = [record[@"id"] isKindOfClass:NSString.class] ? record[@"id"] : @"";
    NSString *selectedThemeID = [self selectedThemeID];
    BOOL selected = [themeID isEqualToString:selectedThemeID];
    BOOL cached = [record[@"cached"] boolValue];
    UIImage *preview = [self previewImageForThemeID:themeID];
    cell.previewImageView.image = preview;
    cell.previewImageView.backgroundColor = preview ? UIColor.clearColor : [self previewFallbackColorForThemeID:themeID];
    NSDictionary<NSString *, NSString *> *descriptions = @{
        @"white-word-wheel": @"Minimal white word-based time display.",
        @"framed-parking": @"Framed motion lock with a clean editorial layout.",
        @"move-the-image": @"Animated artwork with a shifting visual composition.",
        @"animated-art-gallery": @"Gallery-inspired animated artwork lock screen.",
        @"pulse-timeline": @"Modern timeline layout with a subtle pulse animation.",
        @"brushstroke-time": @"Painterly brush textures with an expressive time layout.",
        @"planet-globe-animated-gif": @"Rotating planet lock screen with an atmospheric space look.",
        @"cookie-monster-lock": @"Playful cookie-texture theme with a colorful character backdrop.",
        @"cat-hat-side-clock": @"Whimsical side-positioned clock inspired by a storybook cat.",
        @"xen-cat-side-clock-folder": @"Full folder theme with a whimsical side clock and local assets.",
        @"ios26-big-clock": @"Large glass-style clock arranged across the lock-screen panels.",
        @"oneui8-adaptive-clock": @"Adaptive rounded clock inspired by modern One UI styling.",
        @"aurora-glass": @"Soft aurora gradients, translucent styling, and custom typography.",
        @"ink-garden": @"Ink-wash botanical artwork with a calm editorial mood.",
        @"desert-sun": @"Warm desert palette with spacious, sunlit typography.",
        @"ocean-night": @"Deep ocean blues with a quiet nighttime atmosphere.",
        @"neon-architecture": @"Electric architectural geometry with a futuristic night palette."
    };
    cell.titleLabel.text = record[@"name"];
    cell.descriptionLabel.text = descriptions[themeID] ?: @"A custom SpecialLock theme with local visual assets.";
    cell.statusLabel.text = selected ? @"Currently applied • Tap to reapply" : (cached ? @"Downloaded • Tap to apply • Swipe to delete" : (self.hasCachedCatalog ? @"Available on GitHub • Tap to download" : @"Bundled fallback • Tap to apply"));
    cell.badgeLabel.text = selected ? @"APPLIED" : (cached ? @"DOWNLOADED" : @"GET THEME");
    cell.badgeLabel.textColor = selected ? UIColor.whiteColor : UIColor.labelColor;
    cell.badgeLabel.backgroundColor = selected ? UIColor.systemGreenColor : UIColor.tertiarySystemFillColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.isSynchronizing) {
        return;
    }
    NSDictionary *record = self.themeRecords[indexPath.row];
    NSString *themeID = record[@"id"];
    if (themeID.length == 0) {
        return;
    }
    // Re-fetch cached themes so published GitHub revisions replace stale files.
    BOOL cached = [record[@"cached"] boolValue];
    self.synchronizing = YES;
    self.refreshButton.enabled = NO;
    self.progressView.hidden = NO;
    self.progressView.progress = 0.25;
    self.statusLabel.text = [NSString stringWithFormat:@"%@ %@…", cached ? @"Updating" : @"Downloading", record[@"name"]];
    __weak typeof(self) weakSelf = self;
    [[LPThemeCatalog sharedCatalog] downloadThemeWithID:themeID completion:^(BOOL success) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        self.synchronizing = NO;
        self.refreshButton.enabled = YES;
            self.progressView.hidden = YES;
        if (!success) {
            self.statusLabel.text = @"Theme download failed. Try Refresh, then select the theme again.";
            return;
        }
        [self reloadThemeRecords];
        [self applyThemeID:themeID name:record[@"name"]];
    }];
}

- (void)applyThemeID:(NSString *)themeID name:(NSString *)name {
    CFPreferencesSetAppValue(CFSTR("theme"), (__bridge CFPropertyListRef)themeID, (__bridge CFStringRef)kLPPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
    notify_post(kLPPreferencesChanged.UTF8String);
    self.statusLabel.text = [NSString stringWithFormat:@"%@ applied immediately.", name ?: @"Theme"];
    [self.tableView reloadData];
}

- (NSSet<NSString *> *)hiddenThemeIDs {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)kLPHiddenThemeIDsKey,
                                                        (__bridge CFStringRef)kLPPreferencesDomain);
    NSArray *stored = nil;
    if (value != NULL && CFGetTypeID(value) == CFArrayGetTypeID()) {
        stored = [(__bridge NSArray *)value copy];
    }
    if (value != NULL) {
        CFRelease(value);
    }
    NSMutableSet<NSString *> *hidden = [NSMutableSet set];
    for (id candidate in stored) {
        if ([candidate isKindOfClass:NSString.class] && ((NSString *)candidate).length > 0) {
            [hidden addObject:candidate];
        }
    }
    return hidden;
}

- (void)saveHiddenThemeIDs:(NSSet<NSString *> *)hiddenThemeIDs {
    NSArray *stored = [[hiddenThemeIDs allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    CFPreferencesSetAppValue((__bridge CFStringRef)kLPHiddenThemeIDsKey,
                             (__bridge CFPropertyListRef)stored,
                             (__bridge CFStringRef)kLPPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Only an actual downloaded JSON can be removed. Available GitHub rows stay selectable.
    return !self.isSynchronizing && self.hasCachedCatalog && indexPath.row < self.themeRecords.count && [self.themeRecords[indexPath.row][@"cached"] boolValue];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView canEditRowAtIndexPath:indexPath] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"Delete";
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || ![self tableView:tableView canEditRowAtIndexPath:indexPath]) {
        return;
    }
    NSDictionary *record = self.themeRecords[indexPath.row];
    NSString *themeID = record[@"id"];
    NSString *themeName = record[@"name"];
    UIAlertController *confirmation = [UIAlertController alertControllerWithTitle:@"Remove Downloaded Copy?"
                                                                           message:[NSString stringWithFormat:@"%@ will be removed from this phone only. It stays listed here and can be downloaded again later.", themeName]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        if ([[self selectedThemeID] isEqualToString:themeID]) {
            CFPreferencesSetAppValue(CFSTR("theme"), CFSTR("aurora"), (__bridge CFStringRef)kLPPreferencesDomain);
            CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
        }
        NSString *cachedPath = ROOT_PATH_NS([kLPCachedThemeDirectory stringByAppendingPathComponent:[themeID stringByAppendingPathExtension:@"json"]]);
        [[NSFileManager defaultManager] removeItemAtPath:cachedPath error:nil];
        notify_post(kLPPreferencesChanged.UTF8String);
        [self reloadThemeRecords];
        self.statusLabel.text = [NSString stringWithFormat:@"%@ was removed from the local cache. It remains available to download again.", themeName];
    }]];
    [self presentViewController:confirmation animated:YES completion:nil];
}

- (NSString *)selectedThemeID {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("theme"), (__bridge CFStringRef)kLPPreferencesDomain);
    NSString *themeID = nil;
    if (value != NULL && CFGetTypeID(value) == CFStringGetTypeID()) {
        themeID = [(__bridge NSString *)value copy];
    }
    if (value != NULL) {
        CFRelease(value);
    }
    return themeID ?: @"aurora";
}

@end
