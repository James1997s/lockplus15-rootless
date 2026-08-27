#import "LPHWallpaperPickerController.h"
#import <notify.h>
#import <rootless.h>

static NSString * const kLPWallpaperCatalogURL = @"https://raw.githubusercontent.com/James1997s/lockplus15-rootless/main/wallpapers/catalog.json";
static NSString * const kLPPreferencesDomain = @"com.example.speciallock";
static NSString * const kLPPreferencesChanged = @"com.example.speciallock/preferences.changed";
static NSString * const kLPCachedThemeDirectory = @"/var/mobile/Library/SpecialLock/Themes";

@interface LPHWallpaperPickerController ()
@property(nonatomic,copy) NSString *themeID;
@property(nonatomic,strong) NSArray<NSDictionary *> *wallpapers;
@property(nonatomic,strong) NSMutableDictionary<NSString *,UIImage *> *previewCache;
@property(nonatomic,assign) BOOL loading;
@end

@implementation LPHWallpaperPickerController

- (instancetype)initWithThemeID:(NSString *)themeID {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _themeID = [themeID copy] ?: @"aurora-glass";
        _previewCache = [NSMutableDictionary dictionary];
        self.title = @"Wallpapers";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 104.0;
    self.tableView.tableFooterView = [UIView new];
    [self loadWallpaperCatalog];
}

- (void)loadWallpaperCatalog {
    if (self.loading) return;
    self.loading = YES;
    NSURL *url = [NSURL URLWithString:kLPWallpaperCatalogURL];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSArray *items = [json[@"wallpapers"] isKindOfClass:NSArray.class] ? json[@"wallpapers"] : @[];
        NSMutableArray *valid = [NSMutableArray array];
        for (NSDictionary *item in items) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSString *wallpaperID = item[@"id"], *name = item[@"name"], *relativeURL = item[@"url"];
            if ([wallpaperID isKindOfClass:NSString.class] && wallpaperID.length > 0 && [name isKindOfClass:NSString.class] && name.length > 0 && [relativeURL isKindOfClass:NSString.class] && relativeURL.length > 0 && [relativeURL hasPrefix:@"../"] && ![relativeURL containsString:@"://"] && ![relativeURL containsString:@"..//"]) {
                [valid addObject:item];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.wallpapers = [valid copy];
            self.loading = NO;
            [self.tableView reloadData];
        });
    }] resume];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.wallpapers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"WallpaperCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
        cell.imageView.layer.cornerRadius = 12.0;
        cell.imageView.layer.masksToBounds = YES;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    NSDictionary *wallpaper = self.wallpapers[indexPath.row];
    NSString *wallpaperID = wallpaper[@"id"];
    cell.textLabel.text = wallpaper[@"name"];
    cell.detailTextLabel.text = wallpaper[@"description"] ?: @"Tap to download and apply";
    cell.imageView.image = self.previewCache[wallpaperID] ?: [self placeholderImage];
    [self fetchPreviewForWallpaper:wallpaper atIndexPath:indexPath];
    return cell;
}

- (UIImage *)placeholderImage {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(88, 88), YES, 0.0);
    [[UIColor colorWithRed:0.06 green:0.07 blue:0.12 alpha:1.0] setFill];
    UIRectFill(CGRectMake(0, 0, 88, 88));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)fetchPreviewForWallpaper:(NSDictionary *)wallpaper atIndexPath:(NSIndexPath *)indexPath {
    NSString *wallpaperID = wallpaper[@"id"];
    if (self.previewCache[wallpaperID] != nil) return;
    NSURL *catalogURL = [NSURL URLWithString:kLPWallpaperCatalogURL];
    NSURL *imageURL = [[catalogURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:wallpaper[@"url"]];
    [[[NSURLSession sharedSession] dataTaskWithURL:imageURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = data.length > 0 ? [UIImage imageWithData:data] : nil;
        if (!image) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.previewCache[wallpaperID] = image;
            if ([self.tableView.indexPathsForVisibleRows containsObject:indexPath]) [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        });
    }] resume];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *wallpaper = self.wallpapers[indexPath.row];
    NSString *name = wallpaper[@"name"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name message:@"Download this wallpaper and apply it to the active HTML theme? Only the selected wallpaper is kept locally." preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Download & Apply" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf downloadAndApplyWallpaper:wallpaper]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)downloadAndApplyWallpaper:(NSDictionary *)wallpaper {
    NSURL *catalogURL = [NSURL URLWithString:kLPWallpaperCatalogURL];
    NSURL *imageURL = [[catalogURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:wallpaper[@"url"]];
    [[[NSURLSession sharedSession] dataTaskWithURL:imageURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL ok = error == nil && data.length > 0 && data.length <= (8 * 1024 * 1024) && [UIImage imageWithData:data] != nil;
        if (ok) {
            NSString *path = ROOT_PATH_NS([[kLPCachedThemeDirectory stringByAppendingPathComponent:self.themeID] stringByAppendingPathComponent:@"wallpaper.jpg"]);
            NSURL *url = [NSURL fileURLWithPath:path];
            [[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            ok = [data writeToURL:url options:NSDataWritingAtomic error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                CFPreferencesSetAppValue(CFSTR("wallpaperID"), (__bridge CFStringRef)wallpaper[@"id"], (__bridge CFStringRef)kLPPreferencesDomain);
                CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
                notify_post(kLPPreferencesChanged.UTF8String);
                self.navigationItem.prompt = @"Wallpaper applied";
            } else {
                self.navigationItem.prompt = @"Wallpaper download failed";
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self.navigationItem.prompt = nil; });
        });
    }] resume];
}

@end
