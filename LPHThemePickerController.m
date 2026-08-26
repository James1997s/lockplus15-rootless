#import "LPHThemePickerController.h"
#import <notify.h>

static NSString * const kLPPreferencesDomain = @"com.example.lockplus15";
static NSString * const kLPPreferencesChanged = @"com.example.lockplus15/preferences.changed";

@interface LPHThemePickerController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *records;
@property (nonatomic, copy) NSString *selectedThemeID;
@end

@implementation LPHThemePickerController

- (instancetype)initWithThemeRecords:(NSArray<NSDictionary *> *)records selectedThemeID:(NSString *)selectedThemeID {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _records = [records copy] ?: @[];
        _selectedThemeID = [selectedThemeID copy] ?: @"aurora";
        self.title = @"Theme";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"ThemeCell"];
    self.tableView.rowHeight = 56.0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.records.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ThemeCell" forIndexPath:indexPath];
    NSDictionary *record = self.records[indexPath.row];
    NSString *themeID = record[@"id"];
    cell.textLabel.text = record[@"name"];
    cell.textLabel.numberOfLines = 2;
    cell.accessoryType = [themeID isEqualToString:self.selectedThemeID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *record = self.records[indexPath.row];
    NSString *themeID = record[@"id"];
    if (themeID.length == 0) {
        return;
    }

    CFPreferencesSetAppValue(CFSTR("theme"), (__bridge CFStringRef)themeID, (__bridge CFStringRef)kLPPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kLPPreferencesDomain);
    notify_post(kLPPreferencesChanged.UTF8String);

    self.selectedThemeID = themeID;
    [tableView reloadData];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
