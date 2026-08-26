#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <rootless.h>

@interface LPHRootListController : PSListController
@end

@implementation LPHRootListController

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (NSArray<NSString *> *)themeValues {
    NSMutableSet<NSString *> *themeIDs = [NSMutableSet set];
    NSArray<NSString *> *directories = @[
        ROOT_PATH_NS(@"/Library/LockPlus15/Themes"),
        ROOT_PATH_NS(@"/var/mobile/Library/LockPlus15/Themes"),
    ];
    for (NSString *directory in directories) {
        NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
        for (NSString *file in files) {
            if ([file.pathExtension isEqualToString:@"json"] && ![file isEqualToString:@"catalog.json"]) {
                NSString *themeID = file.stringByDeletingPathExtension;
                if (themeID.length > 0 && themeID.length <= 48) {
                    [themeIDs addObject:themeID];
                }
            }
        }
    }
    if (themeIDs.count == 0) {
        [themeIDs addObject:@"aurora"];
    }
    return [[themeIDs allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSArray<NSString *> *)themeTitles {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSString *themeID in [self themeValues]) {
        [titles addObject:[[themeID stringByReplacingOccurrencesOfString:@"-" withString:@" "] capitalizedString]];
    }
    return titles;
}

- (void)syncThemes {
    notify_post("com.example.lockplus15/preferences.changed");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Theme Sync Started"
                                                                   message:@"SpringBoard will download every valid theme listed in the configured GitHub catalog. Reopen this pane after the sync to see newly available themes."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
