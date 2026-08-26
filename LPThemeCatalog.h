#import <Foundation/Foundation.h>

@interface LPThemeCatalog : NSObject
+ (instancetype)sharedCatalog;
- (NSString *)activeThemeJSON;
- (void)synchronizeCatalogWithCompletion:(void (^)(BOOL activeThemeUpdated))completion;
- (void)synchronizeCatalogWithResult:(void (^)(BOOL success, BOOL activeThemeUpdated))completion;
- (void)synchronizeCatalogWithProgress:(void (^)(NSUInteger completed, NSUInteger total))progress
                            completion:(void (^)(BOOL success, BOOL activeThemeUpdated))completion;
@end
