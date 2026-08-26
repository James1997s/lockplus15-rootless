#import "LPThemeCatalog.h"

#import <rootless.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const kLPPrefsDomain = @"com.example.lockplus15";
static NSString * const kLPDefaultThemeID = @"aurora";
static NSString * const kLPHiddenThemeIDsKey = @"hiddenThemeIDs";
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

- (NSSet<NSString *> *)hiddenThemeIDs {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)kLPHiddenThemeIDsKey,
                                                        (__bridge CFStringRef)kLPPrefsDomain);
    NSArray *storedIDs = nil;
    if (value != NULL && CFGetTypeID(value) == CFArrayGetTypeID()) {
        storedIDs = [(__bridge NSArray *)value copy];
    }
    if (value != NULL) {
        CFRelease(value);
    }
    NSMutableSet<NSString *> *safeIDs = [NSMutableSet set];
    for (id candidate in storedIDs) {
        if ([candidate isKindOfClass:NSString.class] && [self isSafeThemeID:candidate]) {
            [safeIDs addObject:candidate];
        }
    }
    return safeIDs;
}

- (NSURL *)bundledThemeURLForID:(NSString *)themeID {
    NSString *path = ROOT_PATH_NS([@"/Library/LockPlus15/Themes/" stringByAppendingPathComponent:[themeID stringByAppendingPathExtension:@"json"]]);
    return [NSURL fileURLWithPath:path];
}

- (NSURL *)cachedThemeURLForID:(NSString *)themeID {
    NSString *path = ROOT_PATH_NS([@"/var/mobile/Library/LockPlus15/Themes/" stringByAppendingPathComponent:[themeID stringByAppendingPathExtension:@"json"]]);
    return [NSURL fileURLWithPath:path];
}

- (NSURL *)cachedCatalogURL {
    return [NSURL fileURLWithPath:ROOT_PATH_NS(@"/var/mobile/Library/LockPlus15/Themes/catalog.json")];
}

- (NSURL *)cachedAssetURLForThemeID:(NSString *)themeID assetID:(NSString *)assetID {
    NSString *path = ROOT_PATH_NS([@"/var/mobile/Library/LockPlus15/Themes/Assets" stringByAppendingPathComponent:themeID]);
    return [NSURL fileURLWithPath:[path stringByAppendingPathComponent:assetID]];
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
    [self synchronizeCatalogWithResult:^(BOOL success, BOOL activeThemeUpdated) {
        if (completion != nil) {
            completion(activeThemeUpdated);
        }
    }];
}

- (void)synchronizeCatalogWithResult:(void (^)(BOOL success, BOOL activeThemeUpdated))completion {
    [self synchronizeCatalogWithProgress:nil completion:completion];
}

- (void)synchronizeCatalogWithProgress:(void (^)(NSUInteger completed, NSUInteger total))progress
                            completion:(void (^)(BOOL success, BOOL activeThemeUpdated))completion {
    NSString *previousActiveTheme = [self activeThemeJSON] ?: @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        if (progress != nil) {
            progress(0, 1);
        }
    });
    [self refreshCatalogWithCompletion:^(BOOL success) {
        if (progress != nil) {
            progress(1, 1);
        }
        NSString *currentActiveTheme = [self activeThemeJSON] ?: @"";
        BOOL activeThemeUpdated = success && ![previousActiveTheme isEqualToString:currentActiveTheme];
        if (completion != nil) {
            completion(success, activeThemeUpdated);
        }
    }];
}

- (void)refreshCatalogWithCompletion:(void (^)(BOOL success))completion {
    NSURL *catalogURL = [NSURL URLWithString:kLPDefaultCatalogURL];
    void (^finish)(BOOL) = ^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(success);
            }
        });
    };
    if (![self isTrustedCatalogURL:catalogURL]) {
        finish(NO);
        return;
    }

    [[[NSURLSession sharedSession] dataTaskWithURL:catalogURL completionHandler:^(NSData *catalogData, NSURLResponse *response, NSError *error) {
        if (error != nil || ![response isKindOfClass:[NSHTTPURLResponse class]] || ((NSHTTPURLResponse *)response).statusCode != 200) {
            finish(NO);
            return;
        }
        NSDictionary *catalog = [self JSONObjectFromData:catalogData];
        NSArray *allRecords = [catalog[@"themes"] isKindOfClass:[NSArray class]] ? catalog[@"themes"] : nil;
        if (allRecords.count == 0 || allRecords.count > kLPMaximumCatalogThemes) {
            finish(NO);
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
            NSString *name = [candidate[@"name"] isKindOfClass:NSString.class] ? candidate[@"name"] : themeID;
            if (![self isSafeThemeID:themeID] || ![self isSafeRelativeThemeURL:relativeURL] || [seenIDs containsObject:themeID] || name.length == 0 || name.length > 96) {
                continue;
            }
            [seenIDs addObject:themeID];
            [records addObject:@{ @"id": themeID, @"name": name, @"url": relativeURL }];
        }

        NSDictionary *cachedCatalog = @{ @"themes": records };
        NSData *cachedCatalogData = [NSJSONSerialization dataWithJSONObject:cachedCatalog options:0 error:nil];
        NSURL *cachedCatalogURL = [self cachedCatalogURL];
        NSError *directoryError = nil;
        NSError *writeError = nil;
        BOOL madeDirectory = [[NSFileManager defaultManager] createDirectoryAtURL:[cachedCatalogURL URLByDeletingLastPathComponent]
                                                      withIntermediateDirectories:YES
                                                                       attributes:nil
                                                                            error:&directoryError];
        BOOL wroteCatalog = madeDirectory && cachedCatalogData != nil && [cachedCatalogData writeToURL:cachedCatalogURL options:NSDataWritingAtomic error:&writeError];
        finish(wroteCatalog);
    }] resume];
}

- (void)downloadThemeWithID:(NSString *)themeID completion:(void (^)(BOOL success))completion {
    if (![self isSafeThemeID:themeID]) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion != nil) completion(NO); });
        return;
    }
    NSDictionary *catalog = [self JSONObjectFromData:[NSData dataWithContentsOfURL:[self cachedCatalogURL]]];
    NSArray *records = [catalog[@"themes"] isKindOfClass:NSArray.class] ? catalog[@"themes"] : nil;
    NSDictionary *selectedRecord = nil;
    for (id candidate in records) {
        if ([candidate isKindOfClass:NSDictionary.class] && [candidate[@"id"] isEqualToString:themeID]) {
            selectedRecord = candidate;
            break;
        }
    }
    NSURL *catalogURL = [NSURL URLWithString:kLPDefaultCatalogURL];
    if (selectedRecord == nil || ![self isTrustedCatalogURL:catalogURL]) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion != nil) completion(NO); });
        return;
    }
    [self downloadThemeRecord:selectedRecord fromCatalogURL:catalogURL completion:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion != nil) completion(success); });
    }];
}

- (void)downloadThemeAsset:(NSDictionary *)asset themeID:(NSString *)themeID fromCatalogURL:(NSURL *)catalogURL completion:(void (^)(BOOL success))completion {
    NSString *assetID = [asset[@"id"] isKindOfClass:NSString.class] ? asset[@"id"] : nil;
    NSString *relativeURL = [asset[@"url"] isKindOfClass:NSString.class] ? asset[@"url"] : nil;
    NSString *expectedSHA256 = [asset[@"sha256"] isKindOfClass:NSString.class] ? asset[@"sha256"] : nil;
    NSURL *assetURL = [[catalogURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:relativeURL];
    if (![self isSafeThemeID:assetID] || ![self isSafeAssetRelativeURL:relativeURL] || ![self isValidSHA256:expectedSHA256] || ![assetURL.scheme.lowercaseString isEqualToString:@"https"] || ![assetURL.host isEqualToString:catalogURL.host]) {
        completion(NO);
        return;
    }
    [[[NSURLSession sharedSession] dataTaskWithURL:assetURL completionHandler:^(NSData *assetData, NSURLResponse *response, NSError *error) {
        BOOL validResponse = error == nil && [response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode == 200;
        UIImage *image = validResponse && assetData.length <= (2 * 1024 * 1024) ? [UIImage imageWithData:assetData] : nil;
        BOOL validImage = image != nil && image.size.width > 0.0 && image.size.height > 0.0 && image.size.width <= 4096.0 && image.size.height <= 4096.0;
        if (!validImage || ![[self sha256ForData:assetData] isEqualToString:expectedSHA256.lowercaseString]) {
            completion(NO);
            return;
        }
        NSURL *cacheURL = [self cachedAssetURLForThemeID:themeID assetID:assetID];
        NSError *directoryError = nil;
        BOOL madeDirectory = [[NSFileManager defaultManager] createDirectoryAtURL:[cacheURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&directoryError];
        NSData *existing = [NSData dataWithContentsOfURL:cacheURL];
        NSError *writeError = nil;
        BOOL wroteAsset = [existing isEqualToData:assetData] || [assetData writeToURL:cacheURL options:NSDataWritingAtomic error:&writeError];
        completion(madeDirectory && wroteAsset);
    }] resume];
}

- (void)downloadThemeRecord:(NSDictionary *)record fromCatalogURL:(NSURL *)catalogURL completion:(void (^)(BOOL success))completion {
    NSString *themeID = record[@"id"];
    NSString *relativeURL = record[@"url"];
    NSURL *themeURL = [[catalogURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:relativeURL];
    if (![self isSafeThemeID:themeID] || ![themeURL.scheme.lowercaseString isEqualToString:@"https"] || ![themeURL.host isEqualToString:catalogURL.host]) {
        completion(NO);
        return;
    }

    [[[NSURLSession sharedSession] dataTaskWithURL:themeURL completionHandler:^(NSData *themeData, NSURLResponse *response, NSError *error) {
        BOOL validResponse = error == nil && [response isKindOfClass:[NSHTTPURLResponse class]] && ((NSHTTPURLResponse *)response).statusCode == 200;
        if (!validResponse || [self validatedThemeJSONStringFromData:themeData] == nil) {
            completion(NO);
            return;
        }
        NSDictionary *theme = [self JSONObjectFromData:themeData];
        NSArray *assets = [theme[@"assets"] isKindOfClass:NSArray.class] ? theme[@"assets"] : @[];
        dispatch_group_t assetGroup = dispatch_group_create();
        __block BOOL allAssetsSucceeded = YES;
        NSObject *assetLock = [[NSObject alloc] init];
        for (NSDictionary *asset in assets) {
            dispatch_group_enter(assetGroup);
            [self downloadThemeAsset:asset themeID:themeID fromCatalogURL:catalogURL completion:^(BOOL success) {
                @synchronized (assetLock) {
                    allAssetsSucceeded = allAssetsSucceeded && success;
                }
                dispatch_group_leave(assetGroup);
            }];
        }
        dispatch_group_notify(assetGroup, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            BOOL assetsSucceeded = NO;
            @synchronized (assetLock) {
                assetsSucceeded = allAssetsSucceeded;
            }
            if (!assetsSucceeded) {
                completion(NO);
                return;
            }
            NSURL *cacheURL = [self cachedThemeURLForID:themeID];
            NSError *directoryError = nil;
            BOOL madeDirectory = [[NSFileManager defaultManager] createDirectoryAtURL:[cacheURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&directoryError];
            NSData *existing = [NSData dataWithContentsOfURL:cacheURL];
            NSError *writeError = nil;
            BOOL wroteTheme = [existing isEqualToData:themeData] || [themeData writeToURL:cacheURL options:NSDataWritingAtomic error:&writeError];
            completion(madeDirectory && wroteTheme);
        });
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

- (BOOL)isSafeAssetRelativeURL:(NSString *)relativeURL {
    NSString *extension = relativeURL.pathExtension.lowercaseString;
    NSSet<NSString *> *allowedExtensions = [NSSet setWithArray:@[ @"jpg", @"jpeg", @"png" ]];
    return relativeURL.length > 0 && [allowedExtensions containsObject:extension] && ![relativeURL containsString:@"://"] && ![relativeURL containsString:@".."] && ![relativeURL hasPrefix:@"/"];
}

- (BOOL)isValidSHA256:(NSString *)hashValue {
    if (hashValue.length != 64) {
        return NO;
    }
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    return [[hashValue lowercaseString] stringByTrimmingCharactersInSet:hex].length == 0;
}

- (NSString *)sha256ForData:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
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
        NSString *type = [properties[@"type"] isKindOfClass:NSString.class] ? properties[@"type"] : nil;
        NSSet<NSString *> *supportedTypes = [NSSet setWithArray:@[ @"clock", @"date", @"text", @"panel", @"wallpaper", @"blob", @"particle", @"ring", @"image", @"widget", @"overlay" ]];
        if (![elementID isKindOfClass:[NSString class]] || properties == nil || ![supportedTypes containsObject:type]) {
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

    NSArray *assets = [theme[@"assets"] isKindOfClass:NSArray.class] ? theme[@"assets"] : @[];
    if (assets.count > 6) {
        return nil;
    }
    NSMutableSet<NSString *> *assetIDs = [NSMutableSet set];
    for (id candidate in assets) {
        NSDictionary *asset = [candidate isKindOfClass:NSDictionary.class] ? candidate : nil;
        NSString *assetID = [asset[@"id"] isKindOfClass:NSString.class] ? asset[@"id"] : nil;
        NSString *assetURL = [asset[@"url"] isKindOfClass:NSString.class] ? asset[@"url"] : nil;
        NSString *sha256 = [asset[@"sha256"] isKindOfClass:NSString.class] ? asset[@"sha256"] : nil;
        if (![self isSafeThemeID:assetID] || [assetIDs containsObject:assetID] || ![self isSafeAssetRelativeURL:assetURL] || ![self isValidSHA256:sha256]) {
            return nil;
        }
        [assetIDs addObject:assetID];
    }

    NSData *canonicalData = [NSJSONSerialization dataWithJSONObject:theme options:0 error:nil];
    return [[NSString alloc] initWithData:canonicalData encoding:NSUTF8StringEncoding];
}

@end
