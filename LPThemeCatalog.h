#import <Foundation/Foundation.h>

@interface LPThemeCatalog : NSObject
+ (instancetype)sharedCatalog;
- (NSString *)activeThemeJSON;
- (void)synchronizeCatalogWithCompletion:(void (^)(BOOL activeThemeUpdated))completion;
@end
