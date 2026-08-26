#import <UIKit/UIKit.h>

@interface LPNativeThemeRenderer : UIView

- (instancetype)initWithThemeJSONString:(NSString *)themeJSONString;
- (void)reloadWithThemeJSONString:(NSString *)themeJSONString;
- (void)stopRendering;

@end
