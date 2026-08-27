#import <Foundation/Foundation.h>

@interface LPThemeCatalog : NSObject
+ (instancetype)sharedCatalog;
- (NSString *)activeThemeJSON;
@end
