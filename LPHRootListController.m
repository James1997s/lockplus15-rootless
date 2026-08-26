#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <rootless.h>
#import "LPHThemePickerController.h"
#import "LPHThemeManagerController.h"

static NSString * const kLPPreferencesDomain = @"com.example.speciallock";
static NSString * const kLPPreferencesChanged = @"com.example.speciallock/preferences.changed";
static NSString * const kLPThemeDirectory = @"/Library/SpecialLock/Themes";
static NSString * const kLPCachedThemeDirectory = @"/var/mobile/Library/SpecialLock/Themes";

@interface LPHRootListController : PSListController
@end

@implementation LPHRootListController

- (NSArray *)specifiers {
    if (_specifiers != nil) {
        return _specifiers;
    }

    self.title = @"SpecialLock";
    NSMutableArray<PSSpecifier *> *specifiers = [NSMutableArray array];

    PSSpecifier *intro = [PSSpecifier groupSpecifierWithName:nil];
    [intro setProperty:@"Select a downloaded GitHub theme. Changes are sent to SpringBoard immediately." forKey:@"footerText"];
    [specifiers addObject:intro];

    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"Enable SpecialLock"
                                                          target:self
                                                             set:@selector(writePreferenceValue:specifier:)
                                                             get:@selector(readPreferenceValue:)
                                                          detail:nil
                                                            cell:PSSwitchCell
                                                            edit:nil];
    [enabled setProperty:kLPPreferencesDomain forKey:@"defaults"];
    [enabled setProperty:@"enabled" forKey:@"key"];
    [enabled setProperty:@NO forKey:@"default"];
    [enabled setProperty:kLPPreferencesChanged forKey:@"PostNotification"];
    [specifiers addObject:enabled];

    PSSpecifier *theme = [PSSpecifier preferenceSpecifierNamed:@"Theme"
                                                        target:self
                                                           set:nil
                                                           get:nil
                                                        detail:nil
                                                          cell:PSButtonCell
                                                          edit:nil];
    [theme setProperty:kLPPreferencesDomain forKey:@"defaults"];
    [theme setProperty:@"theme" forKey:@"key"];
    [theme setProperty:@"aurora" forKey:@"default"];
    theme.buttonAction = @selector(openThemePicker);
    [specifiers addObject:theme];

    PSSpecifier *sync = [PSSpecifier preferenceSpecifierNamed:@"Theme Manager"
                                                       target:self
                                                          set:nil
                                                          get:nil
                                                       detail:nil
                                                         cell:PSButtonCell
                                                         edit:nil];
    sync.buttonAction = @selector(openThemeManager);
    [specifiers addObject:sync];

    _specifiers = [specifiers copy];
    return _specifiers;
}

- (NSArray<NSDictionary *> *)availableThemeRecords {
    NSString *bundledCatalogPath = ROOT_PATH_NS([kLPThemeDirectory stringByAppendingPathComponent:@"catalog.json"]);
    NSString *cachedCatalogPath = ROOT_PATH_NS([kLPCachedThemeDirectory stringByAppendingPathComponent:@"catalog.json"]);
    NSData *catalogData = [NSData dataWithContentsOfFile:cachedCatalogPath];
    NSDictionary *catalog = catalogData ? [NSJSONSerialization JSONObjectWithData:catalogData options:0 error:nil] : nil;
    BOOL hasCachedCatalog = [catalog[@"themes"] isKindOfClass:NSArray.class];
    NSArray *records = hasCachedCatalog ? catalog[@"themes"] : nil;
    if (!hasCachedCatalog) {
        catalogData = [NSData dataWithContentsOfFile:bundledCatalogPath];
        catalog = catalogData ? [NSJSONSerialization JSONObjectWithData:catalogData options:0 error:nil] : nil;
        records = [catalog[@"themes"] isKindOfClass:NSArray.class] ? catalog[@"themes"] : @[];
    }

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

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) {
        return nil;
    }
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)kLPPreferencesDomain);
    if (value == NULL) {
        return [specifier propertyForKey:@"default"];
    }
    return CFBridgingRelease(value);
}

- (void)writePreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) {
        return;
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)kLPPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
    notify_post(kLPPreferencesChanged.UTF8String);
}

- (void)openThemePicker {
    NSString *selectedThemeID = [self readPreferenceValue:[self themeSpecifier]];
    LPHThemePickerController *picker = [[LPHThemePickerController alloc] initWithThemeRecords:[self availableThemeRecords]
                                                                                selectedThemeID:selectedThemeID];
    [self.navigationController pushViewController:picker animated:YES];
}

- (PSSpecifier *)themeSpecifier {
    for (PSSpecifier *specifier in _specifiers) {
        if ([[specifier propertyForKey:@"key"] isEqualToString:@"theme"]) {
            return specifier;
        }
    }
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:@"Theme" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [specifier setProperty:@"theme" forKey:@"key"];
    [specifier setProperty:@"aurora" forKey:@"default"];
    return specifier;
}

- (void)openThemeManager {
    LPHThemeManagerController *manager = [[LPHThemeManagerController alloc] init];
    [self.navigationController pushViewController:manager animated:YES];
}

@end
