#import "LPHThemePickerController.h"
#import <notify.h>
#import <rootless.h>

static NSString * const kLPPreferencesDomain = @"com.example.lockplus15";
static NSString * const kLPPreferencesChanged = @"com.example.lockplus15/preferences.changed";
static NSString * const kLPCachedThemeDirectory = @"/var/mobile/Library/LockPlus15/Themes";
static NSString * const kLPHiddenThemeIDsKey = @"hiddenThemeIDs";

@interface LPHThemePickerController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *records;
@property (nonatomic, copy) NSString *selectedThemeID;
@property (nonatomic, assign) BOOL hasCachedCatalog;
@end

@implementation LPHThemePickerController

- (instancetype)initWithThemeRecords:(NSArray<NSDictionary *> *)records selectedThemeID:(NSString *)selectedThemeID {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _records = [records copy] ?: @[];
        _selectedThemeID = [selectedThemeID copy] ?: @"aurora";
        self.title = @"Theme";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"ThemeCell"];
    self.tableView.rowHeight = 56.0;
    [self refreshCachedCatalogState];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.records.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ThemeCell" forIndexPath:indexPath];
    NSDictionary *record = self.records[indexPath.row];
    NSString *themeID = record[@"id"];
    cell.textLabel.text = record[@"name"];
    cell.textLabel.numberOfLines = 2;
    cell.accessoryType = [themeID isEqualToString:self.selectedThemeID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)refreshCachedCatalogState {
    NSString *catalogPath = ROOT_PATH_NS([kLPCachedThemeDirectory stringByAppendingPathComponent:@"catalog.json"]);
    NSData *data = [NSData dataWithContentsOfFile:catalogPath];
    NSDictionary *catalog = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    self.hasCachedCatalog = [catalog[@"themes"] isKindOfClass:NSArray.class];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.hasCachedCatalog && indexPath.row < self.records.count;
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
    NSDictionary *record = self.records[indexPath.row];
    NSString *themeID = record[@"id"];
    NSString *themeName = record[@"name"];
    UIAlertController *confirmation = [UIAlertController alertControllerWithTitle:@"Delete Cached Theme?"
                                                                           message:[NSString stringWithFormat:@"%@ will be removed from this phone. It remains on GitHub and can be restored in Theme Manager.", themeName]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        if ([self.selectedThemeID isEqualToString:themeID]) {
            CFPreferencesSetAppValue(CFSTR("theme"), CFSTR("aurora"), (__bridge CFStringRef)kLPPreferencesDomain);
            CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
            self.selectedThemeID = @"aurora";
        }
        [self deleteCachedThemeID:themeID];
        NSMutableArray *updated = [self.records mutableCopy];
        [updated removeObjectAtIndex:indexPath.row];
        self.records = [updated copy];
        [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
        notify_post(kLPPreferencesChanged.UTF8String);
    }]];
    [self presentViewController:confirmation animated:YES completion:nil];
}

- (void)deleteCachedThemeID:(NSString *)themeID {
    NSString *cacheDirectory = ROOT_PATH_NS(kLPCachedThemeDirectory);
    [[NSFileManager defaultManager] removeItemAtPath:[cacheDirectory stringByAppendingPathComponent:[themeID stringByAppendingPathExtension:@"json"]] error:nil];

    NSString *catalogPath = [cacheDirectory stringByAppendingPathComponent:@"catalog.json"];
    NSData *data = [NSData dataWithContentsOfFile:catalogPath];
    NSMutableDictionary *catalog = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] mutableCopy];
    NSArray *records = [catalog[@"themes"] isKindOfClass:NSArray.class] ? catalog[@"themes"] : nil;
    if (records != nil) {
        NSMutableArray *remaining = [NSMutableArray array];
        for (id candidate in records) {
            NSString *candidateID = [candidate[@"id"] isKindOfClass:NSString.class] ? candidate[@"id"] : nil;
            if (![candidateID isEqualToString:themeID]) {
                [remaining addObject:candidate];
            }
        }
        catalog[@"themes"] = remaining;
        NSData *updatedCatalog = [NSJSONSerialization dataWithJSONObject:catalog options:0 error:nil];
        [updatedCatalog writeToFile:catalogPath options:NSDataWritingAtomic error:nil];
    }

    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)kLPHiddenThemeIDsKey,
                                                        (__bridge CFStringRef)kLPPreferencesDomain);
    NSArray *stored = (value != NULL && CFGetTypeID(value) == CFArrayGetTypeID()) ? [(__bridge NSArray *)value copy] : @[];
    if (value != NULL) {
        CFRelease(value);
    }
    NSMutableSet *hidden = [NSMutableSet setWithArray:stored];
    [hidden addObject:themeID];
    NSArray *saved = [[hidden allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    CFPreferencesSetAppValue((__bridge CFStringRef)kLPHiddenThemeIDsKey,
                             (__bridge CFPropertyListRef)saved,
                             (__bridge CFStringRef)kLPPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *record = self.records[indexPath.row];
    NSString *themeID = record[@"id"];
    if (themeID.length == 0) {
        return;
    }

    CFPreferencesSetAppValue(CFSTR("theme"), (__bridge CFStringRef)themeID, (__bridge CFStringRef)kLPPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
    notify_post(kLPPreferencesChanged.UTF8String);

    self.selectedThemeID = themeID;
    [tableView reloadData];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
