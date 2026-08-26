#import <UIKit/UIKit.h>

@interface LPHThemePickerController : UITableViewController

- (instancetype)initWithThemeRecords:(NSArray<NSDictionary *> *)records selectedThemeID:(NSString *)selectedThemeID;

@end
