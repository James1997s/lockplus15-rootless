#import <Foundation/Foundation.h>

@class UIView;

@interface LPOverlayCoordinator : NSObject
+ (instancetype)sharedCoordinator;
- (BOOL)isEnabled;
- (BOOL)isApplyingStockDateVisibility;
- (void)attachToHostView:(UIView *)hostView;
- (void)detachFromHostView:(UIView *)hostView;
- (void)detachCurrentOverlay;
- (void)applyActiveThemeImmediately;
- (void)registerStockDateView:(UIView *)dateView;
- (void)unregisterStockDateView:(UIView *)dateView;
@end
