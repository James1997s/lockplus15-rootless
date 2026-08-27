#import "LPHLockScreenChangerController.h"
#import "LPHThemePickerController.h"
#import "LPHWallpaperPickerController.h"
#import <notify.h>
#import <rootless.h>

static NSString * const kLPPreferencesDomain = @"com.example.speciallock";
static NSString * const kLPThemeDirectory = @"/Library/SpecialLock/Themes";
static NSString * const kLPCachedThemeDirectory = @"/var/mobile/Library/SpecialLock/Themes";
static NSString * const kLPPreferencesChanged = @"com.example.speciallock/preferences.changed";

@interface LPHLockScreenChangerController ()
@property(nonatomic,strong) NSArray<NSDictionary *> *items;
@end

@implementation LPHLockScreenChangerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Lock Screen Changer";
    self.items = @[
        @{ @"title": @"Choose Lock Screen Theme", @"detail": @"Select a downloaded theme and apply it immediately" },
        @{ @"title": @"Choose Wallpaper", @"detail": @"Browse online wallpapers for the current theme" },
        @{ @"title": @"Clock UI Style", @"detail": @"Choose a simple size and placement preset" }
    ];
    self.tableView.rowHeight = 68.0;
    self.tableView.tableFooterView = [UIView new];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"ChangerCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
    NSDictionary *item = self.items[indexPath.row];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"detail"];
    cell.imageView.image = [self glyphForIndex:indexPath.row];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UIImage *)glyphForIndex:(NSInteger)index {
    NSArray *symbols = @[ @"paintbrush", @"photo", @"clock" ];
    UIImage *image = [UIImage systemImageNamed:symbols[MIN(index, 2)]];
    if (image) return image;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(28, 28), NO, 0.0);
    [[UIColor systemTealColor] setFill];
    UIRectFill(CGRectMake(2, 2, 24, 24));
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (NSArray<NSDictionary *> *)availableThemeRecords {
    NSString *bundled = ROOT_PATH_NS([kLPThemeDirectory stringByAppendingPathComponent:@"catalog.json"]);
    NSString *cached = ROOT_PATH_NS([kLPCachedThemeDirectory stringByAppendingPathComponent:@"catalog.json"]);
    NSData *data = [NSData dataWithContentsOfFile:cached];
    NSDictionary *catalog = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![catalog[@"themes"] isKindOfClass:NSArray.class]) {
        data = [NSData dataWithContentsOfFile:bundled];
        catalog = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    }
    NSArray *source = [catalog[@"themes"] isKindOfClass:NSArray.class] ? catalog[@"themes"] : @[];
    NSMutableArray *records = [NSMutableArray array];
    for (NSDictionary *record in source) {
        NSString *themeID = record[@"id"], *name = record[@"name"], *url = record[@"url"];
        if (![themeID isKindOfClass:NSString.class] || !themeID.length || ![name isKindOfClass:NSString.class] || !name.length || ![url isKindOfClass:NSString.class] || !url.length) continue;
        NSString *cachedManifest = ROOT_PATH_NS([kLPCachedThemeDirectory stringByAppendingPathComponent:[themeID stringByAppendingPathExtension:@"json"]]);
        NSString *bundledManifest = ROOT_PATH_NS([kLPThemeDirectory stringByAppendingPathComponent:url]);
        if ([[NSFileManager defaultManager] fileExistsAtPath:cachedManifest] || [[NSFileManager defaultManager] fileExistsAtPath:bundledManifest]) [records addObject:@{ @"id": themeID, @"name": name }];
    }
    return records;
}

- (NSString *)selectedThemeID {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("theme"), (__bridge CFStringRef)kLPPreferencesDomain);
    return CFBridgingRelease(value) ?: @"aurora-glass";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 0) {
        LPHThemePickerController *picker = [[LPHThemePickerController alloc] initWithThemeRecords:[self availableThemeRecords] selectedThemeID:[self selectedThemeID]];
        [self.navigationController pushViewController:picker animated:YES];
    } else if (indexPath.row == 1) {
        [self.navigationController pushViewController:[[LPHWallpaperPickerController alloc] initWithThemeID:[self selectedThemeID]] animated:YES];
    } else {
        [self showClockStyleChooser];
    }
}

- (void)showClockStyleChooser {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clock UI Style" message:@"Choose a preset. It can be changed again at any time." preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *presets = @[
        @{ @"title": @"Compact — Top Left", @"size": @"compact", @"position": @"top-left" },
        @{ @"title": @"Balanced — Center", @"size": @"balanced", @"position": @"center" },
        @{ @"title": @"Large — Lower Center", @"size": @"large", @"position": @"lower-center" }
    ];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *preset in presets) {
        [alert addAction:[UIAlertAction actionWithTitle:preset[@"title"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            CFPreferencesSetAppValue(CFSTR("clockSize"), (__bridge CFStringRef)preset[@"size"], (__bridge CFStringRef)kLPPreferencesDomain);
            CFPreferencesSetAppValue(CFSTR("clockPosition"), (__bridge CFStringRef)preset[@"position"], (__bridge CFStringRef)kLPPreferencesDomain);
            CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
            notify_post(kLPPreferencesChanged.UTF8String);
            weakSelf.navigationItem.prompt = @"Clock style applied";
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ weakSelf.navigationItem.prompt = nil; });
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
