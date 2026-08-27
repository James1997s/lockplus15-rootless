#import "LPThemeCatalog.h"

#import <rootless.h>

static NSString * const kLPPrefsDomain = @"com.example.speciallock";
static NSString * const kLPBundledThemeDirectory = @"/Library/SpecialLock/Themes";

@implementation LPThemeCatalog

+ (instancetype)sharedCatalog {
    static LPThemeCatalog *catalog;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        catalog = [[self alloc] init];
    });
    return catalog;
}

- (BOOL)isSafeThemeID:(NSString *)themeID {
    if (themeID.length == 0 || themeID.length > 48) {
        return NO;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];
    return [[themeID stringByTrimmingCharactersInSet:allowed] length] == 0;
}

- (BOOL)isSafeRelativePath:(NSString *)relativePath {
    if (relativePath.length == 0 || relativePath.length > 180 || [relativePath hasPrefix:@"/"] || [relativePath containsString:@".."] || [relativePath containsString:@"://"] || [relativePath containsString:@"\0"]) {
        return NO;
    }
    for (NSString *part in [relativePath componentsSeparatedByString:@"/"]) {
        if (part.length == 0 || [part isEqualToString:@"."]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)isSafeAssetRelativePath:(NSString *)relativePath {
    NSString *extension = relativePath.pathExtension.lowercaseString;
    NSSet<NSString *> *allowedExtensions = [NSSet setWithArray:@[ @"jpg", @"jpeg", @"png", @"gif" ]];
    return [self isSafeRelativePath:relativePath] && [allowedExtensions containsObject:extension];
}

- (BOOL)isValidSHA256:(NSString *)hashValue {
    if (hashValue.length != 64) {
        return NO;
    }
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    return [[hashValue lowercaseString] stringByTrimmingCharactersInSet:hex].length == 0;
}

- (NSDictionary *)JSONObjectFromData:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

- (NSURL *)bundledThemeURLForID:(NSString *)themeID {
    NSString *path = ROOT_PATH_NS([kLPBundledThemeDirectory stringByAppendingPathComponent:[themeID stringByAppendingPathExtension:@"json"]]);
    return [NSURL fileURLWithPath:path];
}

- (NSString *)firstBundledThemeID {
    NSString *catalogPath = ROOT_PATH_NS([kLPBundledThemeDirectory stringByAppendingPathComponent:@"catalog.json"]);
    NSDictionary *catalog = [self JSONObjectFromData:[NSData dataWithContentsOfFile:catalogPath]];
    NSArray *themes = [catalog[@"themes"] isKindOfClass:NSArray.class] ? catalog[@"themes"] : @[];
    for (NSDictionary *record in themes) {
        NSString *themeID = [record[@"id"] isKindOfClass:NSString.class] ? record[@"id"] : nil;
        if ([self isSafeThemeID:themeID] && [[NSFileManager defaultManager] fileExistsAtPath:[self bundledThemeURLForID:themeID].path]) {
            return themeID;
        }
    }
    return nil;
}

- (NSString *)selectedThemeID {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("theme"), (__bridge CFStringRef)kLPPrefsDomain);
    NSString *themeID = nil;
    if (value != NULL && CFGetTypeID(value) == CFStringGetTypeID()) {
        themeID = [(__bridge NSString *)value copy];
    }
    if (value != NULL) {
        CFRelease(value);
    }
    if ([self isSafeThemeID:themeID] && [[NSFileManager defaultManager] fileExistsAtPath:[self bundledThemeURLForID:themeID].path]) {
        return themeID;
    }
    return [self firstBundledThemeID];
}

- (NSString *)validatedNativeThemeJSONStringFromData:(NSData *)data {
    NSDictionary *theme = [self JSONObjectFromData:data];
    NSString *themeID = [theme[@"id"] isKindOfClass:NSString.class] ? theme[@"id"] : nil;
    NSString *format = [theme[@"format"] isKindOfClass:NSString.class] ? theme[@"format"] : nil;
    NSDictionary *elements = [theme[@"placedElements"] isKindOfClass:NSDictionary.class] ? theme[@"placedElements"] : nil;
    if (![self isSafeThemeID:themeID] || ![format isEqualToString:@"native"] || elements.count == 0 || elements.count > 128) {
        return nil;
    }
    NSArray *assets = [theme[@"assets"] isKindOfClass:NSArray.class] ? theme[@"assets"] : @[];
    if (assets.count > 8) {
        return nil;
    }
    NSMutableDictionary<NSString *, NSString *> *assetPaths = [NSMutableDictionary dictionary];
    for (NSDictionary *asset in assets) {
        NSString *assetID = [asset[@"id"] isKindOfClass:NSString.class] ? asset[@"id"] : nil;
        NSString *assetPath = [asset[@"url"] isKindOfClass:NSString.class] ? asset[@"url"] : nil;
        if (![self isSafeThemeID:assetID] || assetPaths[assetID] != nil || ![self isSafeAssetRelativePath:assetPath]) {
            return nil;
        }
        assetPaths[assetID] = assetPath;
    }
    NSSet<NSString *> *supportedTypes = [NSSet setWithArray:@[ @"clock", @"date", @"word-clock", @"text", @"panel", @"wallpaper", @"blob", @"particle", @"ring", @"image", @"widget", @"overlay", @"ecg-time", @"brushstroke-time", @"battery" ]];
    for (NSString *elementID in elements) {
        NSDictionary *properties = [elements[elementID] isKindOfClass:NSDictionary.class] ? elements[elementID] : nil;
        NSString *type = [properties[@"type"] isKindOfClass:NSString.class] ? properties[@"type"] : nil;
        if (elementID.length == 0 || properties == nil || ![supportedTypes containsObject:type]) {
            return nil;
        }
        for (id key in properties) {
            id value = properties[key];
            NSString *lowercase = [value isKindOfClass:NSString.class] ? [value lowercaseString] : nil;
            if (![key isKindOfClass:NSString.class] || lowercase == nil || [lowercase containsString:@"javascript:"] || [lowercase containsString:@"http://"] || [lowercase containsString:@"https://"] || [lowercase containsString:@"data:"]) {
                return nil;
            }
        }
    }
    NSData *canonicalData = [NSJSONSerialization dataWithJSONObject:theme options:0 error:nil];
    return [[NSString alloc] initWithData:canonicalData encoding:NSUTF8StringEncoding];
}

- (NSString *)activeThemeJSON {
    NSString *themeID = [self selectedThemeID];
    if (themeID.length == 0) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:[self bundledThemeURLForID:themeID]];
    return [self validatedNativeThemeJSONStringFromData:data];
}

@end
