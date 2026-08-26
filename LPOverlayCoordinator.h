#import <Foundation/Foundation.h>

@class UIView;

@interface LPOverlayCoordinator : NSObject
+ (instancetype)sharedCoordinator;
- (void)attachToHostView:(UIView *)hostView;
- (void)detachFromHostView:(UIView *)hostView;
@end
