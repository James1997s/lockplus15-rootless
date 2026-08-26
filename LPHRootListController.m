#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <rootless.h>

static NSString * const kLPThemeDirectory = @"/Library/LockPlus15/Themes";
static NSString * const kLPCachedThemeDirectory = @"/var/mobile/Library/LockPlus15/Themes";

@interface LPHRootListController : PSListController
@end

@implementation LPHRootListController

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        for (PSSpecifier *specifier in _specifiers) {
            if ([[specifier propertyForKey:@"key"] isEqualToString:@"theme"]) {
                [specifier setProperty:[self themeTitles] forKey:@"validTitles"];
                [specifier setProperty:[self themeValues] forKey:@"validValues"];
            }
        }
    }
    return _specifiers;
}

- (NSArray<NSDictionary *> *)availableThemeRecords {
    NSString *catalogPath = ROOT_PATH_NS([kLPThemeDirectory stringByAppendingPathComponent:@"catalog.json"]);
    NSData *catalogData = [NSData dataWithContentsOfFile:catalogPath];
    NSDictionary *catalog = catalogData ? [NSJSONSerialization JSONObjectWithData:catalogData options:0 error:nil] : nil;
    NSArray *records = [catalog[@"themes"] isKindOfClass:NSArray.class] ? catalog[@"themes"] : @[];

    NSMutableArray<NSDictionary *> *available = [NSMutableArray array];
    for (NSDictionary *record in records) {
        NSString *themeID = [record[@"id"] isKindOfClass:NSString.class] ? record[@"id"] : nil;
        NSString *name = [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : nil;
        NSString *relativePath = [record[@"url"] isKindOfClass:NSString.class] ? record[@"url"] : nil;
        if (themeID.length == 0 || name.length == 0 || relativePath.length == 0) {
            continue;
        }

        NSString *bundledPath = ROOT_PATH_NS([kLPThemeDirectory stringByAppendingPathComponent:relativePath]);
        NSString *cachedPath = ROOT_PATH_NS([kLPCachedThemeDirectory stringByAppendingPathComponent:[themeID stringByAppendingPathExtension:@"json"]]);
        if ([[NSFileManager defaultManager] fileExistsAtPath:bundledPath] || [[NSFileManager defaultManager] fileExistsAtPath:cachedPath]) {
            [available addObject:@{ @"id": themeID, @"name": name }];
        }
    }

    return [available sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
}

- (NSArray<NSString *> *)themeValues {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSDictionary *record in [self availableThemeRecords]) {
        [values addObject:record[@"id"]];
    }
    return values.count > 0 ? values : @[ @"aurora" ];
}

- (NSArray<NSString *> *)themeTitles {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSDictionary *record in [self availableThemeRecords]) {
        [titles addObject:record[@"name"]];
    }
    return titles.count > 0 ? titles : @[ @"Aurora" ];
}

- (void)syncThemes {
    notify_post("com.example.lockplus15/preferences.changed");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Theme Sync Started"
                                                                   message:@"SpringBoard is downloading every compatible GitHub theme. Close and reopen this page after a few seconds to refresh the selector."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
