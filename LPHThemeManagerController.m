#import "LPHThemeManagerController.h"

#import <notify.h>
#import <rootless.h>

#import "LPThemeCatalog.h"

static NSString * const kLPPreferencesDomain = @"com.example.lockplus15";
static NSString * const kLPPreferencesChanged = @"com.example.lockplus15/preferences.changed";
static NSString * const kLPThemeDirectory = @"/Library/LockPlus15/Themes";
static NSString * const kLPCachedThemeDirectory = @"/var/mobile/Library/LockPlus15/Themes";
static NSString * const kLPHiddenThemeIDsKey = @"hiddenThemeIDs";

@interface LPHThemeManagerController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *themeRecords;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIBarButtonItem *refreshButton;
@property (nonatomic, strong) UIBarButtonItem *restoreButton;
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
    self.tableView.rowHeight = 54.0;
    self.tableView.refreshControl = [[UIRefreshControl alloc] init];
    [self.tableView.refreshControl addTarget:self action:@selector(refreshThemes) forControlEvents:UIControlEventValueChanged];

    self.refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshThemes)];
    self.restoreButton = [[UIBarButtonItem alloc] initWithTitle:@"Restore" style:UIBarButtonItemStylePlain target:self action:@selector(restoreDeletedThemes)];
    // Do not set leftBarButtonItem here: Settings supplies the Back button there.
    self.navigationItem.rightBarButtonItems = @[ self.refreshButton, self.restoreButton ];

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
    self.restoreButton.enabled = NO;
    self.statusLabel.text = @"Refreshing the GitHub theme list…";
    __weak typeof(self) weakSelf = self;
    [[LPThemeCatalog sharedCatalog] refreshCatalogWithCompletion:^(BOOL success) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        self.synchronizing = NO;
        self.refreshButton.enabled = YES;
        self.restoreButton.enabled = YES;
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
        // A cached catalog lists all remote choices. JSON is downloaded only when
        // the user taps a theme that is not already available locally.
        [available addObject:@{ @"id": themeID, @"name": name, @"remoteOnly": @(!isBundled), @"cached": @(isCached || isBundled) }];
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
    self.restoreButton.enabled = NO;
    self.progressView.hidden = NO;
    self.progressView.progress = 0.0;
    self.statusLabel.text = @"Downloading and validating the GitHub catalog…";

    __weak typeof(self) weakSelf = self;
    [[LPThemeCatalog sharedCatalog] synchronizeCatalogWithProgress:^(NSUInteger completed, NSUInteger total) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        float fraction = total > 0 ? (float)completed / (float)total : 0.0f;
        [self.progressView setProgress:fraction animated:YES];
        self.statusLabel.text = [NSString stringWithFormat:@"Downloading and validating %lu of %lu themes…", (unsigned long)completed, (unsigned long)total];
    } completion:^(BOOL success, BOOL activeThemeUpdated) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        self.synchronizing = NO;
        self.refreshButton.enabled = YES;
        self.restoreButton.enabled = YES;
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const reuseIdentifier = @"ThemeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    NSDictionary *record = self.themeRecords[indexPath.row];
    NSString *selectedThemeID = [self selectedThemeID];
    cell.textLabel.text = record[@"name"];
    if ([record[@"id"] isEqualToString:selectedThemeID]) {
        cell.detailTextLabel.text = @"Selected";
    } else if ([record[@"cached"] boolValue]) {
        cell.detailTextLabel.text = @"Downloaded • Tap to apply • Swipe to delete";
    } else if (self.hasCachedCatalog) {
        cell.detailTextLabel.text = @"Available on GitHub • Tap to download";
    } else {
        cell.detailTextLabel.text = @"Bundled fallback • Tap to apply";
    }
    cell.accessoryType = [record[@"id"] isEqualToString:selectedThemeID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
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
    if ([record[@"cached"] boolValue]) {
        [self applyThemeID:themeID name:record[@"name"]];
        return;
    }

    self.synchronizing = YES;
    self.refreshButton.enabled = NO;
    self.restoreButton.enabled = NO;
    self.progressView.hidden = NO;
    self.progressView.progress = 0.25;
    self.statusLabel.text = [NSString stringWithFormat:@"Downloading %@…", record[@"name"]];
    __weak typeof(self) weakSelf = self;
    [[LPThemeCatalog sharedCatalog] downloadThemeWithID:themeID completion:^(BOOL success) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        self.synchronizing = NO;
        self.refreshButton.enabled = YES;
        self.restoreButton.enabled = YES;
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
    self.statusLabel.text = [NSString stringWithFormat:@"%@ applied. Lock the device to view the new theme.", name ?: @"Theme"];
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
    // Rows are deletable only when they came from the on-device GitHub catalog.
    // Bundled fallback records remain protected until a GitHub refresh creates a cache.
    return !self.isSynchronizing && self.hasCachedCatalog && indexPath.row < self.themeRecords.count;
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

- (void)restoreDeletedThemes {
    if (self.isSynchronizing) {
        return;
    }
    [self saveHiddenThemeIDs:[NSSet set]];
    self.statusLabel.text = @"Deleted GitHub themes restored to the download list. Refreshing…";
    [self refreshThemes];
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
