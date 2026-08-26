#import "LPThemeCatalog.h"

#import <rootless.h>

static NSString * const kLPPrefsDomain = @"com.example.lockplus15";
static NSString * const kLPDefaultThemeID = @"test";
static BOOL const kLPForceBundledTestTheme = YES;
static NSUInteger const kLPMaximumCatalogThemes = 64;
// The public repository is the only trusted remote theme catalog.
static NSString * const kLPDefaultCatalogURL = @"https://raw.githubusercontent.com/James1997s/lockplus15-rootless/main/themes/catalog.json";

@implementation LPThemeCatalog

+ (instancetype)sharedCatalog {
    static LPThemeCatalog *catalog;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        catalog = [[self alloc] init];
    });
    return catalog;
}

- (NSString *)selectedThemeID {
    if (kLPForceBundledTestTheme) {
        return kLPDefaultThemeID;
    }
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("theme"),
                                                        (__bridge CFStringRef)kLPPrefsDomain);
    NSString *themeID = nil;
    if (value != NULL && CFGetTypeID(value) == CFStringGetTypeID()) {
        themeID = [(__bridge NSString *)value copy];
    }
    if (value != NULL) {
        CFRelease(value);
    }
    return [self isSafeThemeID:themeID] ? themeID : kLPDefaultThemeID;
}

- (NSURL *)bundledThemeURLForID:(NSString *)themeID {
    NSString *path = ROOT_PATH_NS([@"/Library/LockPlus15/Themes/" stringByAppendingPathComponent:[themeID stringByAppendingPathExtension:@"json"]]);
    return [NSURL fileURLWithPath:path];
}

- (NSURL *)cachedThemeURLForID:(NSString *)themeID {
    NSString *path = ROOT_PATH_NS([@"/var/mobile/Library/LockPlus15/Themes/" stringByAppendingPathComponent:[themeID stringByAppendingPathExtension:@"json"]]);
    return [NSURL fileURLWithPath:path];
}

- (NSString *)activeThemeJSON {
    NSString *themeID = [self selectedThemeID];
    for (NSURL *url in @[[self cachedThemeURLForID:themeID], [self bundledThemeURLForID:themeID]]) {
        NSString *validatedJSON = [self validatedThemeJSONStringFromData:[NSData dataWithContentsOfURL:url]];
        if (validatedJSON != nil) {
            return validatedJSON;
        }
    }
    return [self validatedThemeJSONStringFromData:[NSData dataWithContentsOfURL:[self bundledThemeURLForID:kLPDefaultThemeID]]];
}

- (void)synchronizeCatalogWithCompletion:(void (^)(BOOL activeThemeUpdated))completion {
    NSString *previousActiveTheme = [self activeThemeJSON] ?: @"";
    NSURL *catalogURL = [NSURL URLWithString:kLPDefaultCatalogURL];
    if (![self isTrustedCatalogURL:catalogURL]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        return;
    }

    [[[NSURLSession sharedSession] dataTaskWithURL:catalogURL completionHandler:^(NSData *catalogData, NSURLResponse *response, NSError *error) {
        if (error != nil || ![response isKindOfClass:[NSHTTPURLResponse class]] || ((NSHTTPURLResponse *)response).statusCode != 200) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        NSDictionary *catalog = [self JSONObjectFromData:catalogData];
        NSArray *allRecords = [catalog[@"themes"] isKindOfClass:[NSArray class]] ? catalog[@"themes"] : nil;
        if (allRecords.count == 0 || allRecords.count > kLPMaximumCatalogThemes) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
        NSMutableSet<NSString *> *seenIDs = [NSMutableSet set];
        for (id candidate in allRecords) {
            if (![candidate isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSString *themeID = [candidate[@"id"] isKindOfClass:[NSString class]] ? candidate[@"id"] : nil;
            NSString *relativeURL = [candidate[@"url"] isKindOfClass:[NSString class]] ? candidate[@"url"] : nil;
            if (![self isSafeThemeID:themeID] || ![self isSafeRelativeThemeURL:relativeURL] || [seenIDs containsObject:themeID]) {
                continue;
            }
            [seenIDs addObject:themeID];
            [records addObject:candidate];
        }
        if (records.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        dispatch_group_t group = dispatch_group_create();
        for (NSDictionary *record in records) {
            dispatch_group_enter(group);
            [self downloadThemeRecord:record fromCatalogURL:catalogURL completion:^{
                dispatch_group_leave(group);
            }];
        }
        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString *currentActiveTheme = [self activeThemeJSON] ?: @"";
            BOOL activeThemeUpdated = ![previousActiveTheme isEqualToString:currentActiveTheme];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(activeThemeUpdated); });
        });
    }] resume];
}

- (void)downloadThemeRecord:(NSDictionary *)record fromCatalogURL:(NSURL *)catalogURL completion:(dispatch_block_t)completion {
    NSString *themeID = record[@"id"];
    NSString *relativeURL = record[@"url"];
    NSURL *themeURL = [[catalogURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:relativeURL];
    if (![themeURL.scheme.lowercaseString isEqualToString:@"https"] || ![themeURL.host isEqualToString:catalogURL.host]) {
        completion();
        return;
    }

    [[[NSURLSession sharedSession] dataTaskWithURL:themeURL completionHandler:^(NSData *themeData, NSURLResponse *response, NSError *error) {
        if (error == nil && [response isKindOfClass:[NSHTTPURLResponse class]] && ((NSHTTPURLResponse *)response).statusCode == 200 && [self validatedThemeJSONStringFromData:themeData] != nil) {
            NSURL *cacheURL = [self cachedThemeURLForID:themeID];
            [[NSFileManager defaultManager] createDirectoryAtURL:[cacheURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            NSData *existing = [NSData dataWithContentsOfURL:cacheURL];
            if (![existing isEqualToData:themeData]) {
                [themeData writeToURL:cacheURL options:NSDataWritingAtomic error:nil];
            }
        }
        completion();
    }] resume];
}

- (BOOL)isTrustedCatalogURL:(NSURL *)catalogURL {
    return catalogURL != nil && [catalogURL.scheme.lowercaseString isEqualToString:@"https"] && catalogURL.host.length > 0 && [catalogURL.path hasSuffix:@"/catalog.json"];
}

- (BOOL)isSafeThemeID:(NSString *)themeID {
    if (themeID.length == 0 || themeID.length > 48) {
        return NO;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];
    return [[themeID stringByTrimmingCharactersInSet:allowed] length] == 0;
}

- (BOOL)isSafeRelativeThemeURL:(NSString *)relativeURL {
    return relativeURL.length > 0 && [relativeURL hasSuffix:@".json"] && ![relativeURL containsString:@"://"] && ![relativeURL containsString:@".."] && ![relativeURL hasPrefix:@"/"];
}

- (NSDictionary *)JSONObjectFromData:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

- (NSString *)validatedThemeJSONStringFromData:(NSData *)data {
    NSDictionary *theme = [self JSONObjectFromData:data];
    NSDictionary *elements = [theme[@"placedElements"] isKindOfClass:[NSDictionary class]] ? theme[@"placedElements"] : nil;
    if (elements.count == 0 || elements.count > 128) {
        return nil;
    }

    for (id elementID in elements) {
        NSDictionary *properties = [elements[elementID] isKindOfClass:[NSDictionary class]] ? elements[elementID] : nil;
        if (![elementID isKindOfClass:[NSString class]] || properties == nil || [properties[@"type"] isEqualToString:@"widget"]) {
            return nil;
        }
        for (id key in properties) {
            id value = properties[key];
            if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]]) {
                return nil;
            }
            if ([[value lowercaseString] containsString:@"javascript:"]) {
                return nil;
            }
        }
    }

    NSData *canonicalData = [NSJSONSerialization dataWithJSONObject:theme options:0 error:nil];
    return [[NSString alloc] initWithData:canonicalData encoding:NSUTF8StringEncoding];
}

@end
