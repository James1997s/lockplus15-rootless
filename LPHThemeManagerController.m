#import "LPHThemeManagerController.h"

#import <notify.h>
#import <rootless.h>

static NSString * const kLPPreferencesDomain = @"com.example.speciallock";
static NSString * const kLPPreferencesChanged = @"com.example.speciallock/preferences.changed";
static NSString * const kLPThemeDirectory = @"/Library/SpecialLock/Themes";

@interface LPHThemeManagerController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *themeRecords;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation LPHThemeManagerController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Theme Manager";
    self.tableView.rowHeight = 56.0;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.bounds.size.width, 76.0)];
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(24.0, 14.0, MAX(1.0, self.view.bounds.size.width - 48.0), 48.0)];
    status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    status.textColor = UIColor.secondaryLabelColor;
    status.numberOfLines = 2;
    status.textAlignment = NSTextAlignmentCenter;
    [header addSubview:status];
    self.statusLabel = status;
    self.tableView.tableHeaderView = header;
    [self reloadThemeRecords];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadThemeRecords];
}

- (void)reloadThemeRecords {
    NSString *catalogPath = ROOT_PATH_NS([kLPThemeDirectory stringByAppendingPathComponent:@"catalog.json"]);
    NSData *catalogData = [NSData dataWithContentsOfFile:catalogPath];
    NSDictionary *catalog = catalogData ? [NSJSONSerialization JSONObjectWithData:catalogData options:0 error:nil] : nil;
    NSArray *records = [catalog[@"themes"] isKindOfClass:NSArray.class] ? catalog[@"themes"] : @[];
    NSMutableArray<NSDictionary *> *available = [NSMutableArray array];
    for (NSDictionary *record in records) {
        NSString *themeID = [record[@"id"] isKindOfClass:NSString.class] ? record[@"id"] : nil;
        NSString *name = [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : nil;
        NSString *relativePath = [record[@"url"] isKindOfClass:NSString.class] ? record[@"url"] : nil;
        if (themeID.length == 0 || name.length == 0 || relativePath.length == 0 || [relativePath hasPrefix:@"/"] || [relativePath containsString:@".."]) {
            continue;
        }
        NSString *themePath = ROOT_PATH_NS([kLPThemeDirectory stringByAppendingPathComponent:relativePath]);
        if ([[NSFileManager defaultManager] fileExistsAtPath:themePath]) {
            [available addObject:@{ @"id": themeID, @"name": name, @"format": [record[@"format"] isKindOfClass:NSString.class] ? record[@"format"] : @"json" }];
        }
    }
    self.themeRecords = [available sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
    self.statusLabel.text = [NSString stringWithFormat:@"%lu themes are installed in SpecialLock. No theme downloads are used.", (unsigned long)self.themeRecords.count];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.themeRecords.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"Installed Themes"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const reuseIdentifier = @"ThemeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    }
    NSDictionary *record = self.themeRecords[indexPath.row];
    BOOL selected = [record[@"id"] isEqualToString:[self selectedThemeID]];
    cell.textLabel.text = record[@"name"];
    cell.detailTextLabel.text = selected ? @"Selected" : ([record[@"format"] isEqualToString:@"folder"] ? @"Installed local HTML theme • Tap to apply" : @"Installed local theme • Tap to apply");
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *record = self.themeRecords[indexPath.row];
    NSString *themeID = record[@"id"];
    if (themeID.length == 0) {
        return;
    }
    CFPreferencesSetAppValue(CFSTR("theme"), (__bridge CFPropertyListRef)themeID, (__bridge CFStringRef)kLPPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
    notify_post(kLPPreferencesChanged.UTF8String);
    self.statusLabel.text = [NSString stringWithFormat:@"%@ applied. Lock the device to view the local theme.", record[@"name"] ?: @"Theme"];
    [self.tableView reloadData];
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
    return themeID ?: @"xen-cat-side-clock-folder";
}

@end
